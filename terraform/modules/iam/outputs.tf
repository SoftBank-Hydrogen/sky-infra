output "execution_role_arns" {
  description = "서비스 키 → 태스크 실행 역할 ARN"
  value       = { for k, r in aws_iam_role.execution : k => r.arn }
}

output "api_task_role_arn" {
  value = aws_iam_role.api.arn
}

output "worker_task_role_arn" {
  value = aws_iam_role.worker.arn
}

output "deployed_app_boundary_arn" {
  description = "sky-platform CloudFormation 템플릿이 사용자 앱 역할에 다는 권한 경계"
  value       = aws_iam_policy.deployed_app_boundary.arn
}

output "platform_deploy_policy_json" {
  description = "github-oidc 모듈의 platform-deploy 역할 인라인 정책"
  value       = data.aws_iam_policy_document.platform_deploy.json
}

output "app_builder_policy_json" {
  description = "github-oidc 모듈의 app-builder 역할 인라인 정책"
  value       = data.aws_iam_policy_document.app_builder.json
}

output "platform_release_policy_json" {
  description = "github-oidc 모듈의 platform-release 역할 인라인 정책"
  value       = data.aws_iam_policy_document.platform_release.json
}
