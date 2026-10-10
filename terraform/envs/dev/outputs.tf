output "github_role_arns" {
  description = "GitHub Actions 저장소 변수에 넣는다 (AWS_PLAN_ROLE_ARN, AWS_APPLY_ROLE_ARN, AWS_PLATFORM_RELEASE_ROLE_ARN 등)"
  value       = module.github_oidc.role_arns
}

output "published_parameters" {
  value = module.published_outputs.parameter_names
}

output "service_url" {
  value = module.edge.service_url
}

output "alb_dns_name" {
  value = module.edge.alb_dns_name
}

output "cognito_user_pool_id" {
  description = "Sky 사용자는 이 풀에 관리자가 직접 만든다"
  value       = module.edge.cognito_user_pool_id
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = module.cluster.cluster_name
}

output "ecs_service_names" {
  value = { api = module.api.service_name, worker = module.worker.service_name, outbox = module.outbox.service_name }
}

output "secret_arns" {
  description = "값은 적용 후 콘솔이나 CLI로 넣는다"
  value       = module.secrets.secret_arns
}

output "state_db_address" {
  value = module.state_db.address
}

output "state_db_secret_arn" {
  value = module.state_db.master_secret_arn
}

output "artifacts_bucket" {
  value = module.artifacts.bucket_name
}

output "job_queue_url" {
  value = module.queue.queue_url
}

output "deployed_app_boundary_arn" {
  description = "sky-platform CloudFormation 템플릿의 PermissionsBoundary 값"
  value       = module.iam.deployed_app_boundary_arn
}

output "platform_release_role_arn" {
  description = "GitHub 저장소 변수 AWS_PLATFORM_RELEASE_ROLE_ARN에 넣는다"
  value       = module.github_oidc.role_arns["platform-release"]
}

output "alarm_topic_arn" {
  value = module.observability.alarm_topic_arn
}

output "shared_database_queue" {
  description = "Opt-in allocation transport only; null when disabled. Shared workload RDS and allocation ECS service are not created."
  value = var.enable_shared_database_queue ? {
    url     = module.shared_database_queue[0].queue_url
    arn     = module.shared_database_queue[0].queue_arn
    dlq_arn = module.shared_database_queue[0].dlq_arn
    name    = module.shared_database_queue[0].queue_name
  } : null
}
