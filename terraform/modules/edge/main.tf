# [EDGE] 도메인, ACM, ALB, Cognito

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_route53_zone" "this" {
  name         = var.zone_name
  private_zone = false
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  # Cognito 기본 도메인 접두어는 리전 안에서 전역 고유해야 함. 계정 ID를 그대로 드러내지 않도록 해시만 씀
  cognito_domain_prefix = coalesce(
    var.cognito_domain_prefix,
    "${var.name_prefix}-${substr(sha1(data.aws_caller_identity.current.account_id), 0, 8)}",
  )
}

# ACM
resource "aws_acm_certificate" "this" {
  domain_name       = var.service_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 검증 레코드 값은 인증서가 만들어진 뒤에야 알 수 있으므로, for_each 키는 설정값(도메인)으로 정한다.
locals {
  validation_options = { for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o }
}

resource "aws_route53_record" "validation" {
  for_each        = toset([var.service_domain])
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = local.validation_options[each.key].resource_record_name
  type            = local.validation_options[each.key].resource_record_type
  ttl             = 300
  records         = [local.validation_options[each.key].resource_record_value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

# ALB
resource "aws_lb" "this" {
  name                       = var.name_prefix
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [var.alb_security_group_id]
  idle_timeout               = 300 # 분석·배포 요청이 오래 걸린다
  drop_invalid_header_fields = true
}

# Fargate(awsvpc) 태스크는 ip 타깃으로만 등록된다.
resource "aws_lb_target_group" "app" {
  name                 = "${var.name_prefix}-app"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = var.app_port
  deregistration_delay = 120

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

  # 로그인을 먼저 거치도록
  dynamic "default_action" {
    for_each = var.enable_auth ? [1] : []
    content {
      type  = "authenticate-cognito"
      order = 1
      authenticate_cognito {
        user_pool_arn       = aws_cognito_user_pool.this[0].arn
        user_pool_client_id = aws_cognito_user_pool_client.alb[0].id
        user_pool_domain    = aws_cognito_user_pool_domain.this[0].domain
      }
    }
  }

  default_action {
    type             = "forward"
    order            = var.enable_auth ? 2 : 1
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_route53_record" "service" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.service_domain
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# 로그인: 자체 가입을 막고 관리자가 사용자를 직접 만듦
resource "aws_cognito_user_pool" "this" {
  count               = var.enable_auth ? 1 : 0
  name                = var.name_prefix
  deletion_protection = "ACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  count        = var.enable_auth ? 1 : 0
  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.this[0].id
}

# ALB 인증 액션은 비밀값이 있는 클라이언트와 authorization code 흐름을 요구한다.
resource "aws_cognito_user_pool_client" "alb" {
  count        = var.enable_auth ? 1 : 0
  name         = "${var.name_prefix}-alb"
  user_pool_id = aws_cognito_user_pool.this[0].id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.service_domain}/oauth2/idpresponse"]
  prevent_user_existence_errors        = "ENABLED"
}
