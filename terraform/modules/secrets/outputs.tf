output "secret_arns" {
  description = "비밀 키 → ARN"
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

output "secret_names" {
  description = "비밀 키 → 이름"
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}
