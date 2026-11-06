import json
import os
import uuid
import datetime
import boto3
import pymysql

sns = boto3.client("sns")


def gd_ip(detail):
    action = detail.get("service", {}).get("action", {})
    for key in ("networkConnectionAction", "awsApiCallAction"):
        ip = action.get(key, {}).get("remoteIpDetails", {}).get("ipAddressV4")
        if ip:
            return ip
    return None


def handler(event, context):
    source = event.get("source", "unknown")
    detail = event.get("detail", {})

    if source == "aws.guardduty":
        event_type = detail.get("type", "unknown")
        source_ip = gd_ip(detail)
    else:
        event_type = detail.get("event_type", "unknown")
        source_ip = detail.get("source_ip")
    severity = float(detail.get("severity", 0) or 0)

    record = {
        "id": str(uuid.uuid4()),
        "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "source": source,
        "event_type": event_type,
        "severity": severity,
        "source_ip": source_ip,
    }

    db_logged = True
    try:
        conn = pymysql.connect(
            host=os.environ["DB_HOST"], user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"], database=os.environ["DB_NAME"],
            connect_timeout=5, autocommit=True,
        )
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO events (id, ts, source, event_type, severity, source_ip, raw) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    (record["id"], record["ts"], source, event_type, severity,
                     source_ip, json.dumps(event)),
                )
        finally:
            conn.close()
    except Exception as exc:
        db_logged = False
        print(f"DB write failed: {exc}")

    record["db_logged"] = db_logged
    sns.publish(
        TopicArn=os.environ["TOPIC_ARN"],
        Subject=f"[SOAR] {event_type}"[:100],
        Message=json.dumps(record, indent=2),
    )
    return {"status": "ok", "db_logged": db_logged}