# [Secrets] 이름만 만든다. 값은 state에 남지 않도록 적용 후 콘솔이나 CLI로 넣는다.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each    = var.secrets
  name        = "${var.name_prefix}/${each.key}"
  description = each.value
}
