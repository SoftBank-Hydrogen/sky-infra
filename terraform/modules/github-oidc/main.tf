# GitHub Actions가 장기 액세스 키 없이 AWS 역할을 위임받게 한다.
# 역할마다 허용할 저장소·브랜치·환경(sub 클레임)을 명시적으로 제한한다.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  issuer_host = "token.actions.githubusercontent.com"
  provider_arn = var.create_provider ? aws_iam_openid_connect_provider.github[0].arn : (
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.issuer_host}"
  )
}

data "aws_caller_identity" "current" {}

# 계정당 하나만 존재할 수 있다. 이미 있으면 create_provider = false.
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_provider ? 1 : 0
  url            = "https://${local.issuer_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "trust" {
  for_each = var.roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # 조직의 immutable subject template 예:
    # repo:SoftBank-Hydrogen@338183202/sky-infra@1412003322:ref:refs/heads/main
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:sub"
      values   = each.value.subjects
    }
  }
}

resource "aws_iam_role" "this" {
  for_each             = var.roles
  name                 = "${var.name_prefix}-${each.key}"
  description          = each.value.description
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  max_session_duration = each.value.max_session_seconds
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = {
    for pair in flatten([
      for role, cfg in var.roles : [
        for arn in cfg.managed_policy_arns : { key = "${role}|${arn}", role = role, arn = arn }
      ]
    ]) : pair.key => pair
  }
  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies
  name     = "${var.name_prefix}-${each.key}"
  role     = aws_iam_role.this[each.key].id
  policy   = each.value
}
