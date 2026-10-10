# sky-platform에 넘기는 값을 SSM Parameter Store에 기록한다.
# 여기 없는 키를 플랫폼이 읽으면 안 된다.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_ssm_parameter" "this" {
  for_each    = var.values
  name        = "/${var.namespace}/${var.environment}/${each.key}"
  type        = "String"
  value       = each.value
  description = "sky-infra outputs contract v${var.contract_version}"
}

resource "aws_ssm_parameter" "contract_version" {
  name  = "/${var.namespace}/${var.environment}/contract_version"
  type  = "String"
  value = tostring(var.contract_version)
}
