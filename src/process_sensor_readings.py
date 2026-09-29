import base64
import json
import os
import time
from datetime import datetime, timezone

import boto3

DLQ_URL = os.environ["DLQ_URL"]
REDSHIFT_WORKGROUP = os.environ["REDSHIFT_WORKGROUP"]
REDSHIFT_DATABASE = os.environ["REDSHIFT_DATABASE"]

TEMPERATURE_MIN_C = -20
TEMPERATURE_MAX_C = 250
PRESSURE_MIN_MBAR = -100
PRESSURE_MAX_MBAR = 100
VALID_SENSOR_TYPES = {"temperature", "pressure"}
REQUIRED_FIELDS = {"device_id", "sensor_type", "reading_value", "unit", "timestamp"}

sqs = boto3.client("sqs")
redshift_data = boto3.client("redshift-data")


def validate_record(record):
    """Return None if the record is valid, or a short reason string if not."""
    missing = REQUIRED_FIELDS - record.keys()
    if missing:
        return f"missing_fields:{','.join(sorted(missing))}"

    sensor_type = record.get("sensor_type")
    if sensor_type not in VALID_SENSOR_TYPES:
        return f"invalid_sensor_type:{sensor_type}"

    try:
        value = float(record.get("reading_value"))
    except (TypeError, ValueError):
        return "non_numeric_reading_value"

    if sensor_type == "temperature" and not (TEMPERATURE_MIN_C <= value <= TEMPERATURE_MAX_C):
        return f"temperature_out_of_range:{value}"

    if sensor_type == "pressure" and not (PRESSURE_MIN_MBAR <= value <= PRESSURE_MAX_MBAR):
        return f"pressure_out_of_range:{value}"

    return None


def send_to_dlq(record, reason):
    sqs.send_message(
        QueueUrl=DLQ_URL,
        MessageBody=json.dumps(
            {
                "record": record,
                "reason": reason,
                "quarantined_at": datetime.now(timezone.utc).isoformat(),
            }
        ),
    )


def write_record_to_redshift(record):
    redshift_data.execute_statement(
        WorkgroupName=REDSHIFT_WORKGROUP,
        Database=REDSHIFT_DATABASE,
        Sql=(
            "INSERT INTO sensor_readings "
            "(device_id, sensor_type, reading_value, unit, reading_timestamp) "
            "VALUES (:device_id, :sensor_type, :reading_value, :unit, :reading_timestamp)"
        ),
        Parameters=[
            {"name": "device_id", "value": record["device_id"]},
            {"name": "sensor_type", "value": record["sensor_type"]},
            {"name": "reading_value", "value": str(float(record["reading_value"]))},
            {"name": "unit", "value": record["unit"]},
            {"name": "reading_timestamp", "value": record["timestamp"]},
        ],
    )


def handler(event, context):
    valid_count = 0
    quarantined_count = 0

    for kinesis_record in event["Records"]:
        payload_bytes = base64.b64decode(kinesis_record["kinesis"]["data"])

        try:
            record = json.loads(payload_bytes)
        except json.JSONDecodeError:
            send_to_dlq(
                {"raw": payload_bytes.decode("utf-8", errors="replace")},
                "invalid_json",
            )
            quarantined_count += 1
            continue

        reason = validate_record(record)
        if reason:
            send_to_dlq(record, reason)
            quarantined_count += 1
        else:
            write_record_to_redshift(record)
            valid_count += 1

    print(
        f"Processed {len(event['Records'])} records: "
        f"{valid_count} written to Redshift, {quarantined_count} quarantined."
    )

    return {
        "records_processed": len(event["Records"]),
        "valid": valid_count,
        "quarantined": quarantined_count,
    }