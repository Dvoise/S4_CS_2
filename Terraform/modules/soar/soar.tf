resource "aws_guardduty_detector" "main" {
  enable = true
}

resource "aws_sns_topic" "alerts" {
  name = "soar-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_iam_role" "lambda_role" {
  name = "soar-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_actions" {
  name = "soar-actions"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.alerts.arn }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "guardduty" {
  name = "soar-guardduty-findings"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_lambda" {
  rule = aws_cloudwatch_event_rule.guardduty.name
  arn  = aws_lambda_function.responder.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.responder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty.arn
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/soar/auth"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "syslog" {
  name              = "/soar/syslog"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "lambda_putevents" {
  name = "soar-putevents"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["events:PutEvents"]
      Resource = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"
    }]
  })
}

resource "aws_lambda_permission" "allow_logs" {
  statement_id  = "AllowCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.auth.arn}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "auth_failures" {
  name            = "auth-failures"
  log_group_name  = aws_cloudwatch_log_group.auth.name
  filter_pattern  = "?\"Failed password\" ?\"Invalid user\" ?\"authentication failure\""
  destination_arn = aws_lambda_function.ingest.arn
  depends_on      = [aws_lambda_permission.allow_logs]
}

resource "aws_cloudwatch_event_rule" "custom_alerts" {
  name = "soar-custom-alerts"
  event_pattern = jsonencode({
    source        = ["soar.cloudwatch"]
    "detail-type" = ["Security Alert"]
  })
}

resource "aws_cloudwatch_event_target" "custom_to_responder" {
  rule = aws_cloudwatch_event_rule.custom_alerts.name
  arn  = aws_lambda_function.responder.arn
}

resource "aws_lambda_permission" "allow_eventbridge_custom" {
  statement_id  = "AllowEventBridgeCustom"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.responder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custom_alerts.arn
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

 data "archive_file" "soar" {
    type        = "zip"
    source_dir  = "${path.module}/lambda"
    output_path = "${path.module}/soar.zip"
  }

  resource "aws_lambda_function" "responder" {
    function_name    = "soar-responder"
    role             = aws_iam_role.lambda_role.arn
    handler          = "responder.handler"
    runtime          = "python3.12"
    filename         = data.archive_file.soar.output_path
    source_code_hash = data.archive_file.soar.output_base64sha256
    timeout          = 30

    vpc_config {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [var.lambda_sg_id]
    }

    environment {
      variables = {
        DB_HOST     = var.db_host
        DB_NAME     = var.db_name
        DB_USER     = var.db_user
        DB_PASSWORD = var.db_password
        TOPIC_ARN   = aws_sns_topic.alerts.arn
      }
    }
  }

  resource "aws_lambda_function" "ingest" {
    function_name    = "soar-ingest"
    role             = aws_iam_role.lambda_role.arn
    handler          = "ingest.handler"
    runtime          = "python3.12"
    filename         = data.archive_file.soar.output_path
    source_code_hash = data.archive_file.soar.output_base64sha256
    timeout          = 30
  }

  resource "aws_iam_role" "response_role" {
  name = "soar-response-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "response_basic" {
  role       = aws_iam_role.response_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "response_actions" {
  name = "soar-response-actions"
  role = aws_iam_role.response_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.alerts.arn },
      { Effect = "Allow", Action = ["ec2:DescribeNetworkAcls", "ec2:DescribeInstances"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:CreateNetworkAclEntry"],
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-acl/${var.nacl_id}" },
      { Effect = "Allow", Action = ["ec2:ModifyNetworkInterfaceAttribute", "ec2:CreateTags"], Resource = "*" },
      { Effect = "Allow", Action = ["autoscaling:DescribeAutoScalingInstances", "autoscaling:EnterStandby"], Resource = "*" }
    ]
  })
}

resource "aws_lambda_function" "block_ip" {
  function_name    = "soar-block-ip"
  role             = aws_iam_role.response_role.arn
  handler          = "block_ip.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.soar.output_path
  source_code_hash = data.archive_file.soar.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      NACL_ID   = var.nacl_id
      TOPIC_ARN = aws_sns_topic.alerts.arn
      ALLOWLIST = join(",", var.allowlist_ips)
    }
  }
}

resource "aws_lambda_function" "quarantine" {
  function_name    = "soar-quarantine"
  role             = aws_iam_role.response_role.arn
  handler          = "quarantine.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.soar.output_path
  source_code_hash = data.archive_file.soar.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ISOLATION_SG_ID     = var.isolation_sg_id
      TOPIC_ARN           = aws_sns_topic.alerts.arn
      HOLD_FOR_FORENSICS  = "false"
    }
  }
}

locals {
  block_rules = {
    "block-logs" = jsonencode({
      source        = ["soar.cloudwatch"]
      "detail-type" = ["Security Alert"]
      detail        = { event_type = ["ssh_invalid_user"] }
    })
    "block-guardduty" = jsonencode({
      source        = ["aws.guardduty"]
      "detail-type" = ["GuardDuty Finding"]
      detail = { type = [
        { prefix = "UnauthorizedAccess:EC2/SSHBruteForce" },
        { prefix = "Recon:EC2/PortProbe" }
      ] }
    })
  }
  quarantine_rules = {
    "quarantine-logs" = jsonencode({
      source        = ["soar.cloudwatch"]
      "detail-type" = ["Security Alert"]
      detail        = { event_type = ["instance_compromised"] }
    })
    "quarantine-guardduty" = jsonencode({
      source        = ["aws.guardduty"]
      "detail-type" = ["GuardDuty Finding"]
      detail = { type = [
        { prefix = "Backdoor:EC2" },
        { prefix = "CryptoCurrency:EC2" },
        { prefix = "Trojan:EC2" }
      ] }
    })
  }
}

resource "aws_cloudwatch_event_rule" "block" {
  for_each      = local.block_rules
  name          = "soar-${each.key}"
  event_pattern = each.value
}

resource "aws_cloudwatch_event_target" "block" {
  for_each = local.block_rules
  rule     = aws_cloudwatch_event_rule.block[each.key].name
  arn      = aws_lambda_function.block_ip.arn
}

resource "aws_lambda_permission" "block" {
  for_each      = local.block_rules
  statement_id  = "AllowEB-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.block_ip.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.block[each.key].arn
}

resource "aws_cloudwatch_event_rule" "quarantine" {
  for_each      = local.quarantine_rules
  name          = "soar-${each.key}"
  event_pattern = each.value
}

resource "aws_cloudwatch_event_target" "quarantine" {
  for_each = local.quarantine_rules
  rule     = aws_cloudwatch_event_rule.quarantine[each.key].name
  arn      = aws_lambda_function.quarantine.arn
}

resource "aws_lambda_permission" "quarantine" {
  for_each      = local.quarantine_rules
  statement_id  = "AllowEB-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.quarantine.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.quarantine[each.key].arn
}