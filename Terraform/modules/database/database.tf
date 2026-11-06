resource "aws_instance" "mysql_db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = var.private_subnet_blue_id
  vpc_security_group_ids = [var.db_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.db_profile.name
  user_data_replace_on_change = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y mysql-server

    systemctl enable mysql
    systemctl start mysql

    sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
    systemctl restart mysql

    mysql -e "CREATE DATABASE IF NOT EXISTS ${var.db_name};"
    mysql -e "CREATE USER IF NOT EXISTS '${var.db_username}'@'%' IDENTIFIED WITH mysql_native_password BY '${var.db_password}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${var.db_name}.* TO '${var.db_username}'@'%';"
    mysql -e "FLUSH PRIVILEGES;"

    mysql -e "CREATE DATABASE IF NOT EXISTS soar;"
    mysql -e "CREATE TABLE IF NOT EXISTS soar.events (id CHAR(36) PRIMARY KEY, ts DATETIME NOT NULL, source VARCHAR(64), event_type VARCHAR(128), severity FLOAT, source_ip VARCHAR(45), raw JSON);"
    mysql -e "CREATE USER IF NOT EXISTS 'soar'@'%' IDENTIFIED WITH mysql_native_password BY '${var.soar_db_password}';"
    mysql -e "GRANT INSERT, SELECT ON soar.events TO 'soar'@'%';"
    mysql -e "FLUSH PRIVILEGES;"
  EOF
  )

  tags = {
    Name = "self-managed-mysql"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "db_ssm_role" {
  name = "db-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "db_ssm" {
  role       = aws_iam_role.db_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "db_profile" {
  name = "db-ssm-profile"
  role = aws_iam_role.db_ssm_role.name
}