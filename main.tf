/* provider "aws" {
  region = var.region
  access_key = var.abc
  secret_key = var.secabc
  
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-unique-cloudtrail-logs-bucket-casestudy-6"
  lifecycle {
    prevent_destroy = true
  }
}

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
          StringLike = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
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





resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id       = aws_vpc.my_vpc.id
  service_name = "com.amazonaws.us-east-2.s3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action   = "s3:*",
        Resource = "*"
      }
    ]
  })
}

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
          "cloudwatch:PutMetricData",   # <- Added permission
          "logs:CreateLogGroup",        # <- Optionally add this if you need to create log groups
          "logs:CreateLogStream",       # <- Optionally add this if you need to create log streams
          "logs:PutLogEvents"           # <- Optionally add this if you need to put log events
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "cloudwatch_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}



resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_s3_bucket_lifecycle_configuration" "my_bucket_lifecycle" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    id     = "transition-rule"
    status = "Enabled"

    filter {
      prefix = "" # Apply the rule to all objects in the bucket
    }

    transition {
      days          = 30       # After 30 days, move to Standard-IA (Infrequent Access)
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90       # After 90 days, move to Glacier
      storage_class = "GLACIER"
    }

    expiration {
      days = 365    # After 365 days, permanently delete objects
    }
  }
}

resource "aws_instance" "my_instance" {
  ami           = "ami-0490fddec0cbeb88b" # Example Amazon Linux 2 AMI
  instance_type = "t2.micro"
  count = 2
  subnet_id     = aws_subnet.my_subnet.id
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  key_name = "ohiokey"
  

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

  EOF

  tags = {
    Name = "MyEC2Instance"
  }
}

resource "aws_cloudtrail" "my_trail" {
  name                          = "my-trail"
  s3_bucket_name                = aws_s3_bucket.my_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
}

*/