mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_region" { defaults = { region = "ap-northeast-2" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_iam_policy_document" { defaults = { json = "{}" } }
}

run "allocation_role_scope" {
  command = plan
  module { source = "../../modules/allocation-worker" }
  variables {
    name_prefix             = "sky-dev"
    cluster_arn             = "arn:aws:ecs:ap-northeast-2:123456789012:cluster/sky-dev"
    cluster_name            = "sky-dev"
    image                   = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sky-platform:1111111111111111111111111111111111111111"
    platform_repository_arn = "arn:aws:ecr:ap-northeast-2:123456789012:repository/sky-platform"
    subnet_ids              = ["subnet-11111111", "subnet-22222222"]
    security_group_id       = "sg-11111111"
    queue_url               = "https://sqs.ap-northeast-2.amazonaws.com/123456789012/shared.fifo"
    queue_arn               = "arn:aws:sqs:ap-northeast-2:123456789012:shared.fifo"
    environment             = { SKY_AWS_REGION = "ap-northeast-2" }
    state_secret_arn        = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds!state-test01"
    identity_secrets        = { SKY_ALB_TRUSTS_JSON = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:trusts-test01", SKY_MEMBERSHIPS_JSON = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:members-test01" }
    registration = {
      version = 1
      settings = {
        pool               = { id = "dev", region = "ap-northeast-2", account_id = "123456789012", instance_id = "sky-dev-workload-pool" }
        admin_secret_arn   = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds!pool-test01"
        app_secret_kms_arn = "arn:aws:kms:ap-northeast-2:123456789012:key/11111111-1111-1111-1111-111111111111"
      }
    }
  }
  assert {
    condition     = aws_iam_role.task.name == "sky-dev-allocation-task" && aws_iam_role.execution.name == "sky-dev-allocation-execution"
    error_message = "Allocation process must have dedicated task and execution roles."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.task.statement : alltrue([
      for a in s.actions : !startswith(a, "iam:") && !startswith(a, "ecr:") && !startswith(a, "cloudformation:") && a != "rds:CreateDBInstance" && a != "secretsmanager:DeleteSecret"
    ])])
    error_message = "Allocator must not build/deploy apps, create IAM roles/RDS, or delete secrets."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.task.statement :
      s.sid != "StateAndPoolCredentials" || toset(s.resources) == toset([
        var.state_secret_arn, var.registration.settings.admin_secret_arn
      ])
    ])
    error_message = "Only explicit state and pool admin secret references may be read as admin credentials."
  }
}
