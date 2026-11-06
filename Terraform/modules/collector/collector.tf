data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_iam_role" "collector_role" {
  name = "collector-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "collector_ssm" {
  role       = aws_iam_role.collector_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "collector_cw" {
  role       = aws_iam_role.collector_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "collector_profile" {
  name = "collector-profile"
  role = aws_iam_role.collector_role.name
}

resource "aws_instance" "collector" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.sg_id]
  iam_instance_profile        = aws_iam_instance_profile.collector_profile.name
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    until curl -s --max-time 5 -o /dev/null http://archive.ubuntu.com; do
      sleep 5
    done

    apt-get update -y
    apt-get install -y rsyslog wget

    cat > /etc/rsyslog.d/10-onprem.conf <<'CONF'
    module(load="imtcp")
    input(type="imtcp" port="514")
    template(name="OnPremFmt" type="string" string="%timegenerated% %hostname% %syslogtag%%msg%\n")
    if ($fromhost-ip startswith "192.168.121.") then {
      action(type="omfile" file="/var/log/onprem-auth.log" template="OnPremFmt")
      stop
    }
    CONF
    touch /var/log/onprem-auth.log
    systemctl restart rsyslog

    wget -q https://amazoncloudwatch-agent-eu-central-1.s3.eu-central-1.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i -E ./amazon-cloudwatch-agent.deb
    echo '{"agent":{"run_as_user":"root"},"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/onprem-auth.log","log_group_name":"/soar/auth","log_stream_name":"onprem-{instance_id}"}]}}}}' > /opt/aws/amazon-cloudwatch-agent/etc/config.json
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json -s
  EOF

  tags = {
    Name = "syslog-collector"
  }
}