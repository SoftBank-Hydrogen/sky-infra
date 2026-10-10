output "state_bucket" {
  description = "envs/*/backend.hcl의 bucket 값"
  value       = aws_s3_bucket.state.bucket
}

output "region" {
  value = var.region
}
