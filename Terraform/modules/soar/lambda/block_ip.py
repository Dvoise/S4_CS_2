import ipaddress
import json
import os
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

NACL_ID = os.environ["NACL_ID"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
ALLOW = {a.strip() for a in os.environ.get("ALLOWLIST", "").split(",") if a.strip()}
NEVER_BLOCK = [ipaddress.ip_network(n) for n in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
    "127.0.0.0/8", "169.254.0.0/16", "0.0.0.0/8")]
MIN_RULE, MAX_RULE = 10, 90  # default allow-all is rule 100, so denies must sit below it


def extract_ip(event):
    detail = event.get("detail", {})
    if event.get("source") != "aws.guardduty":
        return detail.get("source_ip")
    action = detail.get("service", {}).get("action", {})
    for key in ("networkConnectionAction", "awsApiCallAction"):
        ip = action.get(key, {}).get("remoteIpDetails", {}).get("ipAddressV4")
        if ip:
            return ip
    for d in action.get("portProbeAction", {}).get("portProbeDetails", []):
        ip = d.get("remoteIpDetails", {}).get("ipAddressV4")
        if ip:
            return ip
    return None


def blockable(ip):
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False, "invalid address"
    if addr.version != 4:
        return False, "IPv6 not handled"
    if any(addr in n for n in NEVER_BLOCK):
        return False, "private/internal range"
    if ip in ALLOW:
        return False, "allowlisted"
    return True, ""


def handler(event, context):
    ip = extract_ip(event)
    result = {"ip": ip}
    ok, reason = blockable(ip) if ip else (False, "no source IP in event")

    if not ok:
        result.update(action="skipped", reason=reason)
    else:
        try:
            entries = ec2.describe_network_acls(NetworkAclIds=[NACL_ID])["NetworkAcls"][0]["Entries"]
            cidr = f"{ip}/32"
            if any(e.get("CidrBlock") == cidr and e["RuleAction"] == "deny" and not e["Egress"] for e in entries):
                result["action"] = "already_blocked"
            else:
                used = {e["RuleNumber"] for e in entries if not e["Egress"]}
                free = next((n for n in range(MIN_RULE, MAX_RULE + 1) if n not in used), None)
                if free is None:
                    result["action"] = "failed: no free rule numbers"
                else:
                    ec2.create_network_acl_entry(
                        NetworkAclId=NACL_ID, RuleNumber=free, Protocol="-1",
                        RuleAction="deny", Egress=False, CidrBlock=cidr)
                    result.update(action="blocked", rule_number=free)
        except ClientError as exc:
            result["action"] = f"failed: {exc.response['Error']['Code']}"

    sns.publish(TopicArn=TOPIC_ARN, Subject=f"[SOAR] Block IP: {result['action']}"[:100],
                Message=json.dumps(result, indent=2))
    return result