# [Observability] 서비스 서버 로그와 기본 알람
# 로그: API·워커 컨테이너, ECS Exec 세션. 알람은 모두 SNS 토픽 하나로 보낸다.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each          = toset(["api", "worker"])
  name              = "/${var.name_prefix}/${each.key}"
  retention_in_days = var.log_retention_days
}

# 운영자의 ECS Exec 세션 기록
resource "aws_cloudwatch_log_group" "exec" {
  name              = "/${var.name_prefix}/ecs-exec"
  retention_in_days = var.log_retention_days
}

resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
}

locals {
  actions = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# API (ALB)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "no_healthy_target" {
  alarm_name          = "${var.name_prefix}-api-no-healthy-target"
  alarm_description   = "Sky API 정상 타깃이 없다 (서비스 중단)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
  alarm_actions = local.actions
  ok_actions    = local.actions
}

# ALB 자체 5xx와 Sky가 돌려준 5xx를 합쳐 본다.
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${var.name_prefix}-api-http-5xx"
  alarm_description   = "Sky ALB 5xx 급증 (${var.http_5xx_period_seconds}초에 ${var.http_5xx_threshold}건 이상)"
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.http_5xx_threshold
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "total"
    expression  = "FILL(elb, 0) + FILL(target, 0)"
    label       = "ELB + target 5xx"
    return_data = true
  }

  metric_query {
    id = "elb"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      stat        = "Sum"
      period      = var.http_5xx_period_seconds
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  metric_query {
    id = "target"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      stat        = "Sum"
      period      = var.http_5xx_period_seconds
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
        TargetGroup  = var.target_group_arn_suffix
      }
    }
  }

  alarm_actions = local.actions
  ok_actions    = local.actions
}

# ---------------------------------------------------------------------------
# 작업 큐
# ---------------------------------------------------------------------------

# 세 번 실패한 작업이 DLQ에 들어갔다. 사람이 원인을 보고 재처리(redrive)하거나 지운다.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name_prefix}-jobs-dlq-not-empty"
  alarm_description   = "Sky 작업이 반복 실패해 DLQ에 들어갔다"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.dlq_name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# 워커가 뜨지 못하거나 처리가 막혀 작업이 오래 기다린다.
resource "aws_cloudwatch_metric_alarm" "job_waiting_too_long" {
  alarm_name          = "${var.name_prefix}-jobs-waiting-too-long"
  alarm_description   = "Sky 작업이 ${var.max_job_wait_minutes}분 넘게 대기 중이다"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = var.queue_name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.max_job_wait_minutes * 60
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# ---------------------------------------------------------------------------
# 상태 DB
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.name_prefix}-state-db-cpu"
  alarm_description   = "Sky 상태 DB CPU 80% 이상 15분"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "db_free_storage" {
  alarm_name          = "${var.name_prefix}-state-db-free-storage"
  alarm_description   = "Sky 상태 DB 남은 스토리지 2 GiB 미만"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 2 * 1024 * 1024 * 1024
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}
