output "identifier" {
  value = aws_db_instance.this.identifier
}

output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "database_name" {
  value = aws_db_instance.this.db_name
}

output "master_secret_arn" {
  description = "RDS가 관리하는 마스터 비밀(username, password JSON). 값은 교체된다"
  value       = one(aws_db_instance.this.master_user_secret[*].secret_arn)
}
