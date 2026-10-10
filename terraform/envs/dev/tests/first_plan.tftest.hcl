# 빈 계정 첫 plan 회귀 검사. 자격 증명 없이 mock provider로 plan만 한다.
# 계산값(ID, ARN)이 unknown인 상태에서 for_each/count 키가 정해지는지 확인한다.
# 실행: terraform -chdir=terraform/envs/dev init -backend=false && terraform -chdir=terraform/envs/dev test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-2", name = "ap-northeast-2" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:ap-northeast-2:123456789012:cluster/sky-dev" }
  }
}

# imports.tf의 import 대상. mock provider는 import를 처리하지 못하므로 값을 직접 준다.
override_resource {
  target = module.ecr.aws_ecr_repository.this
  values = { arn = "arn:aws:ecr:ap-northeast-2:123456789012:repository/sky-platform", repository_url = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sky-platform" }
}
override_resource {
  target = module.ecr.aws_ecr_lifecycle_policy.this
}
override_resource {
  target = module.secrets.aws_secretsmanager_secret.this["openai-api-key"]
  values = { arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sky-dev/openai-api-key-AAAAAA" }
}
override_resource {
  target = module.secrets.aws_secretsmanager_secret.this["gcp-service-account-key"]
  values = { arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sky-dev/gcp-service-account-key-BBBBBB" }
}
override_resource {
  target = module.github_oidc.aws_iam_openid_connect_provider.github[0]
  values = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
}

variables {
  aws_account_id          = "123456789012"
  infra_apply_policy_arns = []
  platform_image_tag      = "0000000" # platform-image.auto.tfvars 값과 무관하게 돈다
}

run "first_plan" {
  command = plan

  assert {
    condition     = module.api.service_name == "sky-dev-api" && module.worker.service_name == "sky-dev-worker"
    error_message = "서비스 이름이 deploy.yaml·검사 스크립트와 맞아야 한다."
  }

  assert {
    condition     = local.infra_oidc_subject_prefix == "repo:SoftBank-Hydrogen@338183202/sky-infra@1412003322" && local.platform_oidc_subject_prefix == "repo:SoftBank-Hydrogen@338183202/sky-platform@1407769237"
    error_message = "GitHub의 불변 OIDC sub 접두어가 실제 조직·저장소 ID와 맞아야 한다."
  }

  assert {
    condition     = !contains(keys(module.github_oidc.role_arns), "app-builder")
    error_message = "저장소 ID가 확인되지 않은 builder 역할은 만들면 안 된다."
  }
}

run "builder_repository_registered" {
  command = plan
  variables {
    github_builder_repository_id = "987654321"
  }

  assert {
    condition     = local.builder_oidc_subject_prefix == "repo:SoftBank-Hydrogen@338183202/sky-builder@987654321" && contains(keys(module.github_oidc.role_arns), "app-builder")
    error_message = "builder 저장소 ID가 설정되면 해당 불변 주체의 역할을 만들어야 한다."
  }
}
