terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_kinesis_stream" "sensor_events" {
  name        = "${var.project_prefix}-sensor-events"
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_prefix}-dlq"
  message_retention_seconds = 1209600
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution" {
  name               = "${var.project_prefix}-lambda-execution"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid = "WriteLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:eu-west-2:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_prefix}-*:*",
    ]
  }

  statement {
    sid = "ReadKinesisStream"
    actions = [
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListShards",
    ]
    resources = [aws_kinesis_stream.sensor_events.arn]
  }

  statement {
    sid       = "SendToDeadLetterQueue"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
  statement {
    sid = "UseRedshiftDataAPI"
    actions = [
      "redshift-data:ExecuteStatement",
      "redshift-data:DescribeStatement",
      "redshift-data:GetStatementResult",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "GetRedshiftServerlessCredentials"
    actions   = ["redshift-serverless:GetCredentials"]
    resources = ["*"]
  }

}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "${var.project_prefix}-lambda-permissions"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}



data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../src/process_sensor_readings.py"
  output_path = "${path.module}/../../../build/process_sensor_readings.zip"
}

resource "aws_lambda_function" "process_sensor_readings" {
  function_name    = "${var.project_prefix}-process-sensor-readings"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "process_sensor_readings.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      DLQ_URL            = aws_sqs_queue.dlq.url
      REDSHIFT_WORKGROUP = var.redshift_workgroup
      REDSHIFT_DATABASE  = var.redshift_database
    }
  }
}

resource "aws_lambda_event_source_mapping" "kinesis_to_lambda" {
  event_source_arn                   = aws_kinesis_stream.sensor_events.arn
  function_name                      = aws_lambda_function.process_sensor_readings.arn
  starting_position                  = "LATEST"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
}

resource "aws_cloudwatch_metric_alarm" "consumer_lag" {
  alarm_name          = "${var.project_prefix}-consumer-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 1
  metric_name          = "GetRecords.IteratorAgeMilliseconds"
  namespace             = "AWS/Kinesis"
  period                = 300
  statistic             = "Maximum"
  threshold             = 60000
  alarm_description     = "Lambda consumer is falling behind the Kinesis stream by more than 60 seconds"

  dimensions = {
    StreamName = aws_kinesis_stream.sensor_events.name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 1
  metric_name          = "Errors"
  namespace             = "AWS/Lambda"
  period                = 300
  statistic             = "Sum"
  threshold             = 0
  alarm_description     = "The sensor readings Lambda has thrown at least one error in the last 5 minutes"

  dimensions = {
    FunctionName = aws_lambda_function.process_sensor_readings.function_name
  }
}