output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "app_subnet_ids" {
  value = [for s in aws_subnet.app : s.id]
}

output "data_subnet_ids" {
  value = [for s in aws_subnet.data : s.id]
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "worker_security_group_id" {
  value = aws_security_group.worker.id
}

output "data_security_group_id" {
  value = aws_security_group.data.id
}
