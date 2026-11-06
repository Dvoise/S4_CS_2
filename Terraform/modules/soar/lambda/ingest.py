import base64
import gzip
import json
import re
import boto3

events = boto3.client("events")

IP_RE = re.compile(r"from (\d{1,3}(?:\.\d{1,3}){3})")
USER_RE = re.compile(r"(?:for invalid user|for user|for|Invalid user) (\S+)")


def classify(msg):
    if "Invalid user" in msg:
        return "ssh_invalid_user", "5"
    if "Failed password" in msg:
        return "ssh_failed_login", "4"
    if "authentication failure" in msg:
        return "auth_failure", "4"
    return "auth_other", "2"


def handler(event, context):
    payload = json.loads(gzip.decompress(base64.b64decode(event["awslogs"]["data"])))
    origin = "onprem" if payload["logStream"].startswith("onprem-") else "aws"
    entries = []
    for e in payload["logEvents"]:
        msg = e["message"]
        event_type, severity = classify(msg)
        ip = IP_RE.search(msg)
        user = USER_RE.search(msg)
        entries.append({
            "Source": "soar.cloudwatch",
            "DetailType": "Security Alert",
            "Detail": json.dumps({
                "event_type": event_type,
                "severity": severity,
                "source_ip": ip.group(1) if ip else None,
                "user": user.group(1) if user else None,
                "origin": origin,
                "instance_id": payload["logStream"],
                "log_group": payload["logGroup"],
                "message": msg,
            }),
        })
    failed = 0
    for i in range(0, len(entries), 10):
        resp = events.put_events(Entries=entries[i:i + 10])
        failed += resp.get("FailedEntryCount", 0)
    if failed:
        raise RuntimeError(f"{failed} events failed to reach EventBridge")   
    return {"forwarded": len(entries)}