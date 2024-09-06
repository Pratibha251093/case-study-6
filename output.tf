output "s3_bucket_arn" {
  value = aws_s3_bucket.my_bucket.arn
}

output "vpc_endpoint_id" {
  value = aws_vpc_endpoint.s3_endpoint.id
}

output "iam_role_name" {
  value = aws_iam_role.ec2_role.name
}

output "iam_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}
