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
  # A checked-in live registration must not turn the empty-account fixture on.
  enable_shared_database_queue  = false
  enable_shared_workload_pool   = false
  enable_allocation_worker      = false
  enable_dedicated_preparation  = false
  enable_dedicated_worker       = false
  enable_database_cutover_queue = false
  dedicated_target_instance_ids = []
  allocation_worker_image_tag   = ""
  github_builder_repository_id  = "" # 등록 전 상태를 builder.auto.tfvars와 독립적으로 검증한다
  aws_account_id                = "123456789012"
  infra_apply_policy_arns       = []
  platform_image_tag            = "0000000" # platform-image.auto.tfvars 값과 무관하게 돈다
}

run "first_plan" {
  command = plan

  assert {
    condition     = length(module.database_cutover_queue) == 0 && length(aws_iam_role_policy.database_cutover_publisher) == 0 && output.database_cutover_transport == null
    error_message = "Cutover transport and publisher must remain disabled by default."
  }

  assert {
    condition     = length(module.shared_database_queue) == 0
    error_message = "Shared workload queue must remain opt-in; existing environments gain no allocation queue by default."
  }

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

run "cutover_requires_registered_preparation" {
  command = plan
  variables {
    enable_database_cutover_queue = true
  }
  expect_failures = [var.enable_database_cutover_queue]
}

run "cutover_transport_separated" {
  command = plan
  override_resource {
    target          = module.database_cutover_queue[0].aws_sqs_queue.jobs
    override_during = plan
    values = {
      arn = "arn:aws:sqs:ap-northeast-2:123456789012:sky-dev-database-cutover-jobs.fifo"
      id  = "https://sqs.ap-northeast-2.amazonaws.com/123456789012/sky-dev-database-cutover-jobs.fifo"
    }
  }
  variables {
    enable_shared_database_queue  = true
    enable_shared_workload_pool   = true
    enable_dedicated_preparation  = true
    dedicated_target_instance_ids = ["sky-validation-dedicated"]
    enable_database_cutover_queue = true
  }
  assert {
    condition = (
      module.database_cutover_queue[0].queue_name == "sky-dev-database-cutover-jobs.fifo" &&
      module.database_cutover_queue[0].dlq_name == "sky-dev-database-cutover-jobs-dlq.fifo" &&
      length(module.dedicated_worker) == 0 &&
      !output.database_cutover_transport.admission_enabled &&
      !output.database_cutover_transport.worker_enabled
    )
    error_message = "Cutover preparation must create isolated transport without activating execution."
  }
  assert {
    condition = (
      toset(data.aws_iam_policy_document.database_cutover_publisher[0].statement[0].actions) == toset(["sqs:SendMessage", "sqs:GetQueueAttributes"]) &&
      data.aws_iam_policy_document.database_cutover_publisher[0].statement[0].resources == toset([module.database_cutover_queue[0].queue_arn])
    )
    error_message = "Publisher must not receive/delete jobs or acquire database control permissions."
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

run "shared_database_queue_enabled" {
  command = plan
  variables {
    enable_shared_database_queue = true
  }

  assert {
    condition = (
      length(module.shared_database_queue) == 1 &&
      module.shared_database_queue[0].queue_name == "sky-dev-shared-database-jobs.fifo" &&
      module.shared_database_queue[0].dlq_name == "sky-dev-shared-database-jobs-dlq.fifo" &&
      module.shared_database_queue[0].queue_name != module.queue.queue_name
    )
    error_message = "Shared allocation queue and DLQ must be separate from build transport."
  }

  assert {
    condition     = output.shared_database_queue.name == "sky-dev-shared-database-jobs.fifo"
    error_message = "Runtime registration output must identify the dedicated queue."
  }
}

run "shared_workload_pool_requires_queue" {
  command = plan
  variables {
    enable_shared_workload_pool  = true
    enable_shared_database_queue = false
  }
  expect_failures = [var.enable_shared_workload_pool]
}

run "shared_workload_pool_enabled" {
  command = plan
  variables {
    enable_shared_database_queue = true
    enable_shared_workload_pool  = true
  }
  assert {
    condition     = length(module.workload_pool) == 1 && module.workload_pool[0].identifier != module.state_db.identifier
    error_message = "App workloads must never be allocated in the Sky state RDS."
  }
}

run "allocation_worker_requires_published_image" {
  command = plan
  variables {
    enable_shared_database_queue = true
    enable_shared_workload_pool  = true
    enable_allocation_worker     = true
    allocation_worker_image_tag  = ""
  }
  expect_failures = [var.enable_allocation_worker]
}

run "allocation_worker_enabled" {
  command = plan
  variables {
    enable_shared_database_queue = true
    enable_shared_workload_pool  = true
    enable_allocation_worker     = true
    allocation_worker_image_tag  = "1111111111111111111111111111111111111111"
  }
  assert {
    condition     = length(module.allocation_worker) == 1 && module.allocation_worker[0].service_name == "sky-dev-allocation"
    error_message = "Allocation must use a separate service instead of changing the existing build worker."
  }
}

run "dedicated_preparation_default_disabled" {
  command = plan
  assert {
    condition     = length(module.dedicated_preparation) == 0 && length(module.dedicated_worker) == 0 && length(aws_security_group.dedicated_database) == 0
    error_message = "Dedicated resources and workers must remain opt-in."
  }
}
run "dedicated_preparation_requires_registered_pool" {
  command = plan
  variables {
    enable_dedicated_preparation  = true
    dedicated_target_instance_ids = ["sky-validation-dedicated"]
  }
  expect_failures = [var.enable_dedicated_preparation]
}
run "dedicated_worker_requires_immutable_matching_image" {
  command = plan
  variables {
    enable_shared_database_queue  = true
    enable_shared_workload_pool   = true
    enable_dedicated_preparation  = true
    dedicated_target_instance_ids = ["sky-validation-dedicated"]
    enable_dedicated_worker       = true
    dedicated_worker_image_tag    = "1111111111111111111111111111111111111111"
    dedicated_policies_json       = "{\"schema_version\":1,\"policies\":[]}"
  }
  expect_failures = [var.enable_dedicated_worker]
}

run "dedicated_resources_prepared_worker_paused" {
  command = plan
  variables {
    enable_shared_database_queue  = true
    enable_shared_workload_pool   = true
    enable_dedicated_preparation  = true
    dedicated_target_instance_ids = ["sky-validation-dedicated"]
  }
  assert {
    condition     = length(module.dedicated_preparation) == 1 && length(module.dedicated_worker) == 0 && length(aws_iam_role_policy.dedicated_publisher) == 0
    error_message = "Resource preparation must not activate a worker or change outbox permissions."
  }
  assert {
    condition     = aws_db_parameter_group.dedicated[0].family == "postgres17" && length(aws_vpc_security_group_ingress_rule.dedicated_database) == 2
    error_message = "Dedicated targets require TLS PostgreSQL configuration and scoped worker/runtime network access."
  }
}
run "dedicated_worker_registered" {
  command = plan
  variables {
    enable_shared_database_queue  = true
    enable_shared_workload_pool   = true
    enable_dedicated_preparation  = true
    dedicated_target_instance_ids = ["sky-validation-dedicated"]
    enable_dedicated_worker       = true
    dedicated_worker_image_tag    = "1111111111111111111111111111111111111111"
    platform_image_tag            = "1111111111111111111111111111111111111111"
    dedicated_policies_json       = "{\"schema_version\":1,\"policies\":[]}"
  }
  assert {
    condition     = module.dedicated_worker[0].service_name == "sky-dev-dedicated-preparation" && length(aws_iam_role_policy.dedicated_publisher) == 1
    error_message = "Enabled worker must have a separate service and narrowly scoped publisher."
  }
}
