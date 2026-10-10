# Opt-in preparation resources only. Not instantiated by envs/dev, no live apply.
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
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.amazonaws.com" },
      Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  })
  lifecycle {
    precondition {
      condition     = startswith(var.permissions_boundary_arn, "arn:aws:iam::${local.account}:policy/") && startswith(var.state_secret_arn, "arn:aws:secretsmanager:${local.region}:${local.account}:secret:")
      error_message = "State secret and task permission boundary must match caller account/region."
    }
  }
}
locals {
  task_policy = {
    Version = "2012-10-17"
    Statement = [
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
    ]
  }
}
resource "aws_iam_role_policy" "task" {
  name   = "dedicated-preparation"
  role   = aws_iam_role.task.id
  policy = jsonencode(local.task_policy)
}
