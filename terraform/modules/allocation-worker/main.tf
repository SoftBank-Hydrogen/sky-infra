# Allocation-only process; does not execute user source, call AI, build images or deploy ECS apps.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}
locals {
  name          = "${var.name_prefix}-allocation"
  settings      = var.registration.settings
  pool          = local.settings.pool
  secret_prefix = "arn:${data.aws_partition.current.partition}:secretsmanager:${local.pool.region}:${local.pool.account_id}:secret:sky-pool/${local.pool.id}/*"
  pool_arn      = "arn:${data.aws_partition.current.partition}:rds:${local.pool.region}:${local.pool.account_id}:db:${local.pool.instance_id}"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/${var.name_prefix}/allocation"
  retention_in_days = 14
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}
resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = [var.platform_repository_arn]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = values(var.identity_secrets)
  }
}
resource "aws_iam_role_policy" "execution" {
  name   = "allocation-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "ConsumeAllocations"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
    resources = [var.queue_arn]
  }
  statement {
    sid       = "StateAndPoolCredentials"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [var.state_secret_arn, local.settings.admin_secret_arn]
  }
  statement {
    sid       = "CreatePoolAppSecret"
    actions   = ["secretsmanager:CreateSecret", "secretsmanager:TagResource"]
    resources = [local.secret_prefix]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/sky-pool-id"
      values   = [local.pool.id]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/sky-database-role"
      values   = ["shared_workload"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/sky-managed"
      values   = ["true"]
    }
  }
  statement {
    sid       = "InspectAppSecretNames"
    actions   = ["secretsmanager:DescribeSecret"]
    resources = [local.secret_prefix]
  }
  statement {
    sid       = "ReadOwnedPoolAppSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:GetResourcePolicy"]
    resources = [local.secret_prefix]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/sky-pool-id"
      values   = [local.pool.id]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/sky-database-role"
      values   = ["shared_workload"]
    }
  }
  statement {
    sid       = "AppSecretEncryption"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [local.settings.app_secret_kms_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.pool.region}.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:SecretARN"
      values   = [local.secret_prefix]
    }
  }
  statement {
    sid       = "InspectPoolOwnership"
    actions   = ["rds:ListTagsForResource"]
    resources = [local.pool_arn]
  }
  statement {
    sid       = "ReadPoolInventory"
    actions   = ["rds:DescribeDBInstances", "ec2:DescribeSecurityGroups", "sts:GetCallerIdentity"]
    resources = ["*"]
  }
  statement {
    sid       = "ProtectAllocationTask"
    actions   = ["ecs:UpdateTaskProtection", "ecs:GetTaskProtection"]
    resources = ["arn:${data.aws_partition.current.partition}:ecs:${local.pool.region}:${local.pool.account_id}:task/${var.cluster_name}/*"]
  }
}
resource "aws_iam_role_policy" "task" {
  name   = "allocation-only"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

module "service" {
  source                 = "../ecs-service"
  name                   = local.name
  cluster_arn            = var.cluster_arn
  image                  = var.image
  command                = ["worker", "--mode", "shared-database-queue"]
  cpu                    = 256
  memory                 = 512
  execution_role_arn     = aws_iam_role.execution.arn
  task_role_arn          = aws_iam_role.task.arn
  subnet_ids             = var.subnet_ids
  security_group_id      = var.security_group_id
  min_count              = var.min_count
  max_count              = 1
  enable_execute_command = false
  stop_timeout_seconds   = 120
  environment = merge(var.environment, {
    SKY_SHARED_DATABASE_QUEUE_URL  = var.queue_url
    SKY_SHARED_DATABASE_POOL_JSON  = jsonencode(var.registration)
    SKY_ALLOCATION_TASK_PROTECTION = "required"
  })
  secrets           = var.identity_secrets
  log_group_name    = aws_cloudwatch_log_group.this.name
  log_stream_prefix = "allocation"
  depends_on        = [aws_iam_role_policy.execution, aws_iam_role_policy.task]
}
