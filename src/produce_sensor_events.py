import argparse
import json
import random
import time
from datetime import datetime, timezone

import boto3

STREAM_NAME = "zaki-streaming-pipeline-sensor-events"
REGION = "eu-west-2"

DEVICE_IDS = {
    "temperature": ["dryer-temp-01", "dryer-temp-02", "mill-temp-01"],
    "pressure": ["classifier-pressure-01", "classifier-pressure-02", "mill-pressure-01"],
}

VALID_RANGES = {
    "temperature": {"min": 0, "max": 250, "unit": "celsius"},
    "pressure": {"min": -100, "max": 100, "unit": "mbar"},
}

INVALID_CHANCE = 0.05

kinesis = boto3.client("kinesis", region_name=REGION)


def generate_event():
    sensor_type = random.choice(["temperature", "pressure"])
    device_id = random.choice(DEVICE_IDS[sensor_type])
    value_range = VALID_RANGES[sensor_type]

    is_invalid = random.random() < INVALID_CHANCE

    if is_invalid:
        reading_value = value_range["max"] + random.uniform(50, 500)
    else:
        reading_value = round(random.uniform(value_range["min"], value_range["max"]), 2)

    return {
        "device_id": device_id,
        "sensor_type": sensor_type,
        "reading_value": reading_value,
        "unit": value_range["unit"],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def send_event(event):
    kinesis.put_record(
        StreamName=STREAM_NAME,
        Data=json.dumps(event),
        PartitionKey=event["device_id"],
    )


def main():
    parser = argparse.ArgumentParser(description="Simulate sensor readings into the Kinesis stream.")
    parser.add_argument("--count", type=int, default=20, help="Number of events to send")
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Seconds to wait between events (use 0 for a burst with no delay)",
    )
    args = parser.parse_args()

    for i in range(args.count):
        event = generate_event()
        send_event(event)
        print(f"Sent event {i + 1}/{args.count}: {event}")
        if args.interval > 0:
            time.sleep(args.interval)

    print(f"Done. Sent {args.count} events to {STREAM_NAME}.")


if __name__ == "__main__":
    main()
    