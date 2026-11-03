import json
import os
import uuid
import datetime
import boto3

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
sns = boto3.client("sns")


def handler(event, context):
    source = event.get("source", "unknown")
    detail = event.get("detail", {})

    if source == "aws.guardduty":
        event_type = detail.get("type", "unknown")
    else:
        event_type = detail.get("event_type", "unknown")
    severity = str(detail.get("severity", 0))

    record = {
        "event_id": str(uuid.uuid4()),
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "source": source,
        "event_type": event_type,
        "severity": severity,
        "raw": json.dumps(event),
    }

    table.put_item(Item=record)

    sns.publish(
        TopicArn=os.environ["TOPIC_ARN"],
        Subject=f"[SOAR] {event_type}"[:100],
        Message=json.dumps(record, indent=2),
    )
    return {"status": "ok"}