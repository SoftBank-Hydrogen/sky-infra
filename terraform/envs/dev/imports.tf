# A안(state 유실) 정리 때 지우지 않고 남긴 자원을 B안 state로 가져온다. (2026-10-10)
# 첫 apply로 state에 들어간 뒤에는 아무 일도 하지 않는다. 그 뒤 이 파일을 지워도 된다.
#   - ECR sky-platform: 서비스 서버 이미지가 들어 있다
#   - Secrets Manager 2개: 값이 들어 있다. 지우면 7일 동안 같은 이름을 만들 수 없다
#   - GitHub OIDC 공급자: 계정당 하나
# 비밀 ARN 끝의 6자리는 Secrets Manager가 붙인 임의값이다.

import {
  to = module.ecr.aws_ecr_repository.this
  id = "sky-platform"
}

import {
  to = module.ecr.aws_ecr_lifecycle_policy.this
  id = "sky-platform"
}

import {
  to = module.secrets.aws_secretsmanager_secret.this["openai-api-key"]
  id = "arn:aws:secretsmanager:${var.region}:${var.aws_account_id}:secret:sky-dev/openai-api-key-J4o8zr"
}

import {
  to = module.secrets.aws_secretsmanager_secret.this["gcp-service-account-key"]
  id = "arn:aws:secretsmanager:${var.region}:${var.aws_account_id}:secret:sky-dev/gcp-service-account-key-O6FZNr"
}

import {
  to = module.github_oidc.aws_iam_openid_connect_provider.github[0]
  id = "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
}
