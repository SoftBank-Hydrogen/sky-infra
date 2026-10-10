output "role_arns" {
  description = "역할 이름(접두어 제외) → ARN"
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "provider_arn" {
  value = local.provider_arn
}
