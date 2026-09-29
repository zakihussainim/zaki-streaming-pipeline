terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "zaki-streaming-pipeline-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:zakihussainim/zaki-streaming-pipeline:*",
        "repo:zakihussainim@*/zaki-streaming-pipeline@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "zaki-streaming-pipeline-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid = "ReadWriteTerraformState"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]
  }

  statement {
    sid = "ManageKinesisStream"
    actions = [
      "kinesis:CreateStream",
      "kinesis:DeleteStream",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListStreams",
      "kinesis:ListTagsForStream",
      "kinesis:TagResource",
      "kinesis:UntagResource",
      "kinesis:UpdateStreamMode",
    ]
    resources = [
      "arn:aws:kinesis:eu-west-2:${data.aws_caller_identity.current.account_id}:stream/zaki-streaming-pipeline-*",
    ]
  }


  statement {
    sid = "ManageLambdaFunction"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:ListVersionsByFunction",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
    ]
    resources = [
      "arn:aws:lambda:eu-west-2:${data.aws_caller_identity.current.account_id}:function:zaki-streaming-pipeline-*",
    ]
  }

  statement {
    sid = "ManageLambdaEventSourceMapping"
    actions = [
      "lambda:CreateEventSourceMapping",
      "lambda:GetEventSourceMapping",
      "lambda:UpdateEventSourceMapping",
      "lambda:DeleteEventSourceMapping",
      "lambda:ListEventSourceMappings",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageProjectIAMRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/zaki-streaming-pipeline-*",
    ]
  }

  statement {
    sid = "ManageSQSDeadLetterQueue"
    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:GetQueueAttributes",
      "sqs:SetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ListQueues",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "sqs:ListQueueTags",
    ]
    resources = [
      "arn:aws:sqs:eu-west-2:${data.aws_caller_identity.current.account_id}:zaki-streaming-pipeline-*",
    ]
  }

  statement {
    sid = "ManageLambdaLogGroup"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:logs:eu-west-2:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/zaki-streaming-pipeline-*",
    ]
  }

  statement {
    sid = "ManageCloudWatchAlarms"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource",
    ]
    resources = [
      "arn:aws:cloudwatch:eu-west-2:${data.aws_caller_identity.current.account_id}:alarm:zaki-streaming-pipeline-*",
    ]
  }

  statement {
    sid = "ManageRedshiftServerless"
    actions = [
      "redshift-serverless:CreateNamespace",
      "redshift-serverless:DeleteNamespace",
      "redshift-serverless:GetNamespace",
      "redshift-serverless:UpdateNamespace",
      "redshift-serverless:ListNamespaces",
      "redshift-serverless:CreateWorkgroup",
      "redshift-serverless:DeleteWorkgroup",
      "redshift-serverless:GetWorkgroup",
      "redshift-serverless:UpdateWorkgroup",
      "redshift-serverless:ListWorkgroups",
      "redshift-serverless:TagResource",
      "redshift-serverless:UntagResource",
      "redshift-serverless:ListTagsForResource",
    ]
    resources = ["*"]
  }
  statement {
    sid = "ReadDefaultVPCNetworking"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
    ]
    resources = ["*"]

  }
}



resource "aws_iam_role_policy" "github_actions_permissions" {
  name   = "zaki-streaming-pipeline-github-actions-permissions"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}