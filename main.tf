provider "aws" {
  region     = var.region
  access_key = var.abc
  secret_key = var.secabc
}

data "aws_caller_identity" "current" {}

# VPC for EC2 Instances
resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "my-vpc"
  }
}

# S3 Bucket for CloudTrail logs
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-unique-cloudtrail-logs-bucket-casestudy-6"

  lifecycle {
    prevent_destroy = true
  }
}

# S3 Public Access Block
resource "aws_s3_bucket_public_access_block" "my_bucket_access_block" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

# S3 Bucket Policy for CloudTrail with enforced server-side encryption
resource "aws_s3_bucket_policy" "my_bucket_policy" {
  bucket = aws_s3_bucket.my_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = [
          "s3:PutObject"
        ],
        Resource = "${aws_s3_bucket.my_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
        }
      },
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ],
        Resource = aws_s3_bucket.my_bucket.arn
      }
    ]
  })
}

# S3 Lifecycle Configuration for cost-effective storage
resource "aws_s3_bucket_lifecycle_configuration" "my_bucket_lifecycle" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    id     = "transition-rule"
    status = "Enabled"

    filter {
      prefix = "" # Apply the rule to all objects in the bucket
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# VPC Endpoint for accessing S3 without internet
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id       = aws_vpc.my_vpc.id
  service_name = "com.amazonaws.${var.region}.s3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action   = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "${aws_s3_bucket.my_bucket.arn}",
          "${aws_s3_bucket.my_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM Role for EC2 Instance to access S3 and CloudWatch
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy for EC2 Role to access S3, CloudWatch Logs, and SSM
resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ssm:GetParameter"
        ],
        Resource = [
          "${aws_s3_bucket.my_bucket.arn}",
          "${aws_s3_bucket.my_bucket.arn}/*",
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/my/cloudwatch/config"
        ]
      }
    ]
  })
}

# IAM Instance Profile for EC2 Instances
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# SSM Parameter for CloudWatch Agent Configuration
resource "aws_ssm_parameter" "cloudwatch_config" {
  name  = "/my/cloudwatch/config"
  type  = "String"
  value = <<-EOF
  {
    "agent": {
      "metrics_collection_interval": 60,
      "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
    },
    "logs": {
      "logs_collected": {
        "files": {
          "collect_list": [
            {
              "file_path": "/var/log/messages",
              "log_group_name": "/aws/ec2/instance/logs",
              "log_stream_name": "{instance_id}/messages",
              "timestamp_format": "%b %d %H:%M:%S"
            }
          ]
        }
      }
    }
  }
  EOF
}

# EC2 Instances with CloudWatch Agent
resource "aws_instance" "my_instance" {
  ami           = "ami-0490fddec0cbeb88b" 
  instance_type = "t2.micro"
  count         = 2
  subnet_id     = aws_subnet.my_subnet.id
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  key_name      = "ohiokey"

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-cloudwatch-agent
    sleep 60
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c ssm:/my/cloudwatch/config \
    -s

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a start

    aws s3 cp s3://my-unique-cloudtrail-logs-bucket-casestudy-6/cloudwatch-config.json /var/log

    s3_BUCKET="my-unique-cloudtrail-logs-bucket-casestudy-6"

    if [ -z "$S3_BUCKET" ]; then
      echo "S3 bucket name is required."
      exit 1
    fi

    # List all objects from S3
    echo "Listing all files and objects in the s3 bucket: $S3_BUCKET"
    aws s3 ls "s3://$S3_BUCKET/" --recursive

    if [ $? -eq 0 ]; then 
      echo "Successfully listed all objects in the S3 bucket"
    else 
      echo "Failed to list objects in the S3 bucket"
      exit 1
    fi
  EOF

  tags = {
    Name = "MyEC2Instance"
  }
}

# CloudTrail to log EC2 and S3 activities
resource "aws_cloudtrail" "my_trail" {
  name                          = "my-trail"
  s3_bucket_name                = aws_s3_bucket.my_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::my-unique-cloudtrail-logs-bucket-casestudy-6/"]
    }
  }
}

output "vpc_id" {
  value = aws_vpc.my_vpc.id
}

output "subnet_id" {
  value = aws_subnet.my_subnet.id
}
