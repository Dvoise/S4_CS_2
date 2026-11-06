import datetime
import json
import os
import re
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client("ec2")
asg = boto3.client("autoscaling")
sns = boto3.client("sns")

ISOLATION_SG = os.environ["ISOLATION_SG_ID"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
HOLD = os.environ.get("HOLD_FOR_FORENSICS", "false").lower() == "true"
ID_RE = re.compile(r"^i-[0-9a-f]{8,17}$")


def extract_instance(event):
    detail = event.get("detail", {})
    if event.get("source") == "aws.guardduty":
        return detail.get("resource", {}).get("instanceDetails", {}).get("instanceId")
    return detail.get("instance_id")


def handler(event, context):
    detail = event.get("detail", {})
    iid = extract_instance(event)
    reason = str(detail.get("type") or detail.get("event_type") or "unknown")
    result = {"instance": iid, "reason": reason}

    if not iid or not ID_RE.match(iid):
        result["action"] = "skipped: no valid instance id"
    else:
        try:
            members = asg.describe_auto_scaling_instances(InstanceIds=[iid])["AutoScalingInstances"]
            if not members:
                result["action"] = "skipped: not a web-tier instance, manual response required"
            else:
                if HOLD:  # keep the instance for forensics, ASG launches a replacement
                    asg.enter_standby(InstanceIds=[iid],
                                      AutoScalingGroupName=members[0]["AutoScalingGroupName"],
                                      ShouldDecrementDesiredCapacity=False)
                inst = ec2.describe_instances(InstanceIds=[iid])["Reservations"][0]["Instances"][0]
                eni = next(n["NetworkInterfaceId"] for n in inst["NetworkInterfaces"]
                           if n["Attachment"]["DeviceIndex"] == 0)
                ec2.modify_network_interface_attribute(NetworkInterfaceId=eni, Groups=[ISOLATION_SG])
                ec2.create_tags(Resources=[iid], Tags=[
                    {"Key": "soar-status", "Value": "quarantined"},
                    {"Key": "soar-reason", "Value": reason[:200]},
                    {"Key": "soar-time", "Value": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
                ])
                result.update(action="quarantined", forensic_hold=HOLD)
        except (ClientError, StopIteration) as exc:
            result["action"] = f"failed: {getattr(exc, 'response', {}).get('Error', {}).get('Code', 'error')}"

    sns.publish(TopicArn=TOPIC_ARN, Subject=f"[SOAR] Quarantine: {result['action']}"[:100],
                Message=json.dumps(result, indent=2))
    return result                                                                           