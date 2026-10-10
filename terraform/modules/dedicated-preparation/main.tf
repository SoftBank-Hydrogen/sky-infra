# Opt-in preparation resources; no live apply is performed by this module.
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
locals {
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.region
  rds     = "arn:aws:rds:${local.region}:${local.account}"
  targets = [for id in var.target_instance_ids : "${local.rds}:db:${id}"]
  secrets = "arn:aws:secretsmanager:${local.region}:${local.account}:secret:rds!*"
}
module "queue" {
  source      = "../queue"
  name_prefix = "${var.name_prefix}-dedicated-database"
}
resource "aws_iam_role" "task" {
  name                 = "${var.name_prefix}-dedicated-preparation-task"
  permissions_boundary = var.create_permissions_boundary ? aws_iam_policy.boundary[0].arn : var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.amazonaws.com" },
      Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  })
  lifecycle {
    precondition {
      condition     = (var.create_permissions_boundary ? var.permissions_boundary_arn == null : try(startswith(var.permissions_boundary_arn, "arn:aws:iam::${local.account}:policy/"), false)) && startswith(var.state_secret_arn, "arn:aws:secretsmanager:${local.region}:${local.account}:secret:")
      error_message = "State secret and task permission boundary must match caller account/region."
    }
  }
}
locals {
  task_policy = {
    Version = "2012-10-17"
    Statement = concat([
      { Sid = "ConsumeDedicatedQueue", Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"], Resource = [module.queue.queue_arn] },
      { Sid = "StateCredentials", Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"], Resource = [var.state_secret_arn] },
      { Sid = "ReadOnlyInventory", Effect = "Allow", Action = ["rds:DescribeDBInstances", "rds:DescribeDBSubnetGroups", "rds:DescribeDBParameters", "ec2:DescribeSecurityGroups"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = local.region } } },
      { Sid = "InspectOwnership", Effect = "Allow", Action = ["rds:ListTagsForResource"], Resource = concat(local.targets, ["${local.rds}:db:${var.source_instance_id}"]) },
      { Sid = "CreateExactTargets", Effect = "Allow", Action = ["rds:CreateDBInstance"], Resource = local.targets,
        Condition = {
          StringEquals = { "aws:RequestTag/sky-managed" = "true", "aws:RequestTag/sky-database-role" = "dedicated_workload", "rds:DatabaseEngine" = "postgres" }
          Bool         = { "rds:StorageEncrypted" = "true", "rds:PubliclyAccessible" = "false", "rds:ManageMasterUserPassword" = "true" }
        }
      },
      { Sid       = "TagExactTargets", Effect = "Allow", Action = ["rds:AddTagsToResource"], Resource = local.targets,
        Condition = { StringEquals = { "aws:RequestTag/sky-managed" = "true", "aws:RequestTag/sky-database-role" = "dedicated_workload" } }
      },
      { Sid = "RegisteredRdsConfiguration", Effect = "Allow", Action = ["rds:CreateDBInstance"], Resource = ["${local.rds}:subgrp:${var.subnet_group}", "${local.rds}:pg:${var.parameter_group}", "${local.rds}:og:default:postgres-17"] },
      { Sid       = "RdsManagedSecretCreation", Effect = "Allow", Action = ["secretsmanager:CreateSecret", "secretsmanager:TagResource"], Resource = local.secrets,
        Condition = { StringEquals = { "aws:RequestTag/aws:rds:primaryDBInstanceArn" = local.targets } }
      },
      { Sid       = "ReadExactTargetManagedSecrets", Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"], Resource = local.secrets,
        Condition = { StringEquals = { "secretsmanager:ResourceTag/aws:rds:primaryDBInstanceArn" = local.targets } }
      },
      { Sid = "DescribeManagedEncryptionKeys", Effect = "Allow", Action = ["kms:DescribeKey"], Resource = "arn:aws:kms:${local.region}:${local.account}:key/*" }
      ], var.cluster_name == "" ? [] : [{
        Sid      = "ProtectPreparationTask", Effect = "Allow", Action = ["ecs:UpdateTaskProtection", "ecs:GetTaskProtection"],
        Resource = ["arn:aws:ecs:${local.region}:${local.account}:task/${var.cluster_name}/*"]
    }])
  }
}
resource "aws_iam_role_policy" "task" {
  name   = "dedicated-preparation"
  role   = aws_iam_role.task.id
  policy = jsonencode(local.task_policy)
}
resource "aws_iam_policy" "boundary" {
  count  = var.create_permissions_boundary ? 1 : 0
  name   = "${var.name_prefix}-dedicated-preparation-boundary"
  policy = jsonencode(local.task_policy)
}
