# [IAM] 서비스 서버(API·워커)와 GitHub Actions 역할의 권한
#   main.tf   공통 값, 태스크 실행 역할, API 태스크 역할
#   worker.tf 워커 태스크 역할, 사용자 앱 역할 권한 경계
#   github.tf GitHub OIDC 역할에 넣는 정책 (역할 자체는 github-oidc 모듈이 만든다)
#
# 원칙: 사용자 앱을 만들고 지우는 AWS 권한은 워커만 갖는다. API는 큐에 작업을 넣고 상태를 읽고 쓰기만 한다.

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
  account   = data.aws_caller_identity.current.account_id
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition

  log_group_arn      = { for k, name in var.log_group_names : k => "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${name}" }
  exec_log_group_arn = "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${var.exec_log_group_name}"
  cluster_arn        = "arn:${local.partition}:ecs:${local.region}:${local.account}:cluster/${var.cluster_name}"
}

# ---------------------------------------------------------------------------
# 태스크 실행 역할 (ECS 에이전트가 이미지 pull, 로그, 비밀 주입에 쓴다)
# 서비스마다 따로 두어 각 서비스가 필요한 비밀만 주입받게 한다.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

resource "aws_iam_role" "execution" {
  for_each           = var.services
  name               = "${var.name_prefix}-${each.key}-execution"
  description        = "Sky ${each.key} task execution: image pull, logs, secret injection"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

data "aws_iam_policy_document" "execution" {
  for_each = var.services

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid       = "PullPlatformImage"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = [var.platform_repository_arn]
  }
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.log_group_arn[each.key]}:*"]
  }
  dynamic "statement" {
    for_each = length(each.value.secret_arns) > 0 ? [1] : []
    content {
      sid       = "ReadInjectedSecrets"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = each.value.secret_arns
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  for_each = var.services
  name     = "${var.name_prefix}-${each.key}-execution"
  role     = aws_iam_role.execution[each.key].id
  policy   = data.aws_iam_policy_document.execution[each.key].json
}

# ---------------------------------------------------------------------------
# 두 태스크 역할이 함께 쓰는 문장: 상태 DB 비밀, 파일 저장소, ECS Exec
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "task_common" {
  statement {
    sid = "ReadStateDbSecret"
    # RDS가 비밀번호를 교체하므로 앱이 접속할 때 직접 읽는다.
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [var.state_db_secret_arn]
  }

  statement {
    sid       = "ListArtifacts"
    actions   = ["s3:ListBucket"]
    resources = [var.artifacts_bucket_arn]
  }
  statement {
    sid       = "ReadWriteArtifacts"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${var.artifacts_bucket_arn}/*"]
  }
  statement {
    sid       = "DeleteTemporaryArtifacts"
    actions   = ["s3:DeleteObject"]
    resources = ["${var.artifacts_bucket_arn}/tmp/*"]
  }

  statement {
    sid = "EcsExecChannel"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "EcsExecLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  statement {
    sid       = "EcsExecSessionLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${local.exec_log_group_arn}:*"]
  }
}

resource "aws_iam_policy" "task_common" {
  name        = "${var.name_prefix}-task-common"
  description = "Sky API and worker: state DB secret, artifacts, ECS Exec"
  policy      = data.aws_iam_policy_document.task_common.json
}

# ---------------------------------------------------------------------------
# API 태스크 역할: UI·API 요청 처리, 작업을 큐에 넣기만 한다
# ---------------------------------------------------------------------------

resource "aws_iam_role" "api" {
  name               = "${var.name_prefix}-api-task"
  description        = "Sky API: serves UI and API, enqueues jobs"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

data "aws_iam_policy_document" "api" {
  statement {
    sid       = "EnqueueJobs"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
    resources = concat([var.queue_arn], var.shared_database_queue_arns)
  }
}

resource "aws_iam_role_policy" "api" {
  name   = "${var.name_prefix}-api-task"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

resource "aws_iam_role_policy_attachment" "api_common" {
  role       = aws_iam_role.api.name
  policy_arn = aws_iam_policy.task_common.arn
}
