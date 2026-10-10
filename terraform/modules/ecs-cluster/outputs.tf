output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "capacity_providers_ready" {
  description = "서비스가 용량 공급자 연결 뒤에 만들어지도록 의존 관계에 쓴다"
  value       = aws_ecs_cluster_capacity_providers.this.id
}
