mock_provider "aws" {
  mock_resource "aws_iam_policy" { defaults = { arn = "arn:aws:iam::123456789012:policy/sky-test-dedicated-preparation-boundary" } }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_region" { defaults = { region = "ap-northeast-2" } }
}
variables {
  name_prefix              = "sky-test"
  state_secret_arn         = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:state-test01"
  source_instance_id       = "sky-shared-pool"
  target_instance_ids      = ["sky-game-dedicated"]
  subnet_group             = "sky-db-subnets"
  parameter_group          = "sky-db-tls"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/sky-task-boundary"
}
run "preparation_scope" {
  command = plan
  assert {
    condition     = aws_iam_role.task.permissions_boundary == var.permissions_boundary_arn && aws_iam_role.task.name == "sky-test-dedicated-preparation-task"
    error_message = "Preparation must have a dedicated bounded task role."
  }
  assert {
    condition     = module.queue.queue_name == "sky-test-dedicated-database-jobs.fifo"
    error_message = "Preparation needs a distinct FIFO queue."
  }
  assert {
    condition     = alltrue([for s in local.task_policy.Statement : alltrue([for a in s.Action : !startswith(a, "iam:") && !startswith(a, "ecs:") && !startswith(a, "ecr:") && !startswith(a, "cloudformation:") && a != "rds:DeleteDBInstance" && a != "rds:ModifyDBInstance"])])
    error_message = "Preparation cannot deploy apps, escalate IAM or delete/modify databases."
  }
  assert {
    condition     = local.task_policy.Statement[4].Resource == local.targets && local.task_policy.Statement[4].Condition.Bool["rds:ManageMasterUserPassword"] == "true"
    error_message = "Create must be pinned to explicit targets and managed credentials."
  }
  assert {
    condition     = local.task_policy.Statement[8].Condition.StringEquals["secretsmanager:ResourceTag/aws:rds:primaryDBInstanceArn"] == local.targets
    error_message = "Target credentials cannot expose unrelated RDS secrets."
  }
}
run "reject_foreign_boundary" {
  command = plan
  variables {
    permissions_boundary_arn = "arn:aws:iam::999999999999:policy/foreign"
  }
  expect_failures = [aws_iam_role.task]
}

run "managed_boundary_and_scoped_task_protection" {
  command = apply
  variables {
    create_permissions_boundary = true
    permissions_boundary_arn    = null
    cluster_name                = "sky-test"
  }
  assert {
    condition     = length(aws_iam_policy.boundary) == 1 && aws_iam_policy.boundary[0].policy == jsonencode(local.task_policy)
    error_message = "Managed boundary must cap the role at the same exact preparation scope."
  }
  assert {
    condition     = local.task_policy.Statement[10].Resource == ["arn:aws:ecs:ap-northeast-2:123456789012:task/sky-test/*"] && local.task_policy.Statement[10].Action == ["ecs:UpdateTaskProtection", "ecs:GetTaskProtection"]
    error_message = "Worker can protect only tasks in its registered cluster."
  }
}
