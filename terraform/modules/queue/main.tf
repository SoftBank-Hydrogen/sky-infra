# [Queue] API → 워커 작업 전달 (A안의 프로세스 내 스레드를 대체)
# FIFO로 만든다.
#   MessageGroupId = 앱 ID        → 같은 앱의 배포·DB 작업은 한 번에 하나씩 순서대로 처리
#   MessageDeduplicationId = 시도 ID → API 재시도로 같은 작업이 두 번 들어가지 않음
# 작업은 몇 분~수십 분 걸리므로 워커가 처리 중 ChangeMessageVisibility로 가시성 시간을 늘린다.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-jobs-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 1209600 # 14일 (최대)
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "jobs" {
  name                        = "${var.name_prefix}-jobs.fifo"
  fifo_queue                  = true
  content_based_deduplication = false # 시도 ID를 중복 제거 ID로 직접 넣는다
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"
  visibility_timeout_seconds  = var.visibility_timeout_seconds
  message_retention_seconds   = var.message_retention_seconds
  receive_wait_time_seconds   = 20
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.jobs.arn]
  })
}

# TLS가 아닌 접근을 거부한다.
resource "aws_sqs_queue_policy" "tls_only" {
  for_each = {
    jobs = aws_sqs_queue.jobs
    dlq  = aws_sqs_queue.dlq
  }
  queue_url = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = each.value.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
