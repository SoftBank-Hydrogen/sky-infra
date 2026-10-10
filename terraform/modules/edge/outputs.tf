output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "CloudWatch 지표의 LoadBalancer 차원 값"
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "CloudWatch 지표의 TargetGroup 차원 값"
  value       = aws_lb_target_group.app.arn_suffix
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "service_url" {
  value = "https://${var.service_domain}"
}

output "cognito_user_pool_id" {
  description = "사용자는 이 풀에 관리자가 직접 만든다"
  value       = var.enable_auth ? aws_cognito_user_pool.this[0].id : null
}

output "cognito_login_domain" {
  value = var.enable_auth ? "${aws_cognito_user_pool_domain.this[0].domain}.auth.${data.aws_region.current.region}.amazoncognito.com" : null
}
