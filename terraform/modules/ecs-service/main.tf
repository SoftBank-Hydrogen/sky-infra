# [ECS Service] Fargate 서비스 하나 (태스크 정의 + 서비스 + 오토스케일링)
# API(ALB 뒤, 요청 수 기준 확장)와 워커(큐 길이 기준 0~N 확장)가 이 모듈을 각각 쓴다.
# 이미지 배포는 태스크 정의 교체 + 서비스 task_definition 수정만 일어나야 한다
# (scripts/check_platform_image_plan.py가 이 두 자원 주소를 검사한다).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_region" "current" {}

locals {
  container_name = "sky-platform"
  scaled         = var.max_count > var.min_count
}

resource "aws_ecs_task_definition" "this" {
  enable_fault_injection   = false
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # 이미지가 바뀌면 새 리비전을 만들고 이전 리비전은 등록 해제하지 않는다 (롤백 대상으로 남김)
  skip_destroy = true

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_gib
  }

  container_definitions = jsonencode([merge(
    {
      name        = local.container_name
      image       = var.image
      essential   = true
      stopTimeout = var.stop_timeout_seconds

      environment = [for k in sort(keys(var.environment)) : { name = k, value = var.environment[k] }]
      secrets     = [for k in sort(keys(var.secrets)) : { name = k, valueFrom = var.secrets[k] }]

      linuxParameters = { initProcessEnabled = true }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = var.log_stream_prefix
        }
      }
    },
    var.command == null ? {} : { command = var.command },
    var.container_port == null ? {} : {
      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
    },
  )])
}

resource "aws_ecs_service" "this" {
  name                   = var.name
  cluster                = var.cluster_arn
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = var.min_count
  enable_execute_command = var.enable_execute_command
  propagate_tags         = "SERVICE"

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = var.target_group_arn == null ? null : 60

  # 새 태스크가 뜨지 못하면 ECS가 직전 태스크 정의로 되돌린다.
  # 이때 state는 새 리비전을 가리키므로 다음 plan에 서비스 차이가 보인다.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = local.container_name
      container_port   = var.container_port
    }
  }

  # 태스크 수는 오토스케일링이 정한다.
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [terraform_data.ready]
}

# 대상 그룹의 리스너 연결, 클러스터 용량 공급자 연결이 끝난 뒤에 서비스를 만든다.
resource "terraform_data" "ready" {
  input = var.depends_on_ids
}

# ---------------------------------------------------------------------------
# 오토스케일링
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "this" {
  count              = local.scaled ? 1 : 0
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${split("/", var.cluster_arn)[1]}/${aws_ecs_service.this.name}"
  min_capacity       = var.min_count
  max_capacity       = var.max_count
}

# API: 대상당 ALB 요청 수 기준
resource "aws_appautoscaling_policy" "requests" {
  count              = local.scaled && var.request_scaling != null ? 1 : 0
  name               = "${var.name}-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.request_scaling.requests_per_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = var.request_scaling.resource_label
    }
  }
}

# API: CPU 기준 (요청 수가 적어도 분석 요청이 무거울 때)
resource "aws_appautoscaling_policy" "cpu" {
  count              = local.scaled && var.cpu_target_percent != null ? 1 : 0
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# 워커: 큐 길이 기준. 대상 추적은 태스크 0개에서 나눗셈이 안 되므로 단계 조정을 쓴다.
#   늘리기: 대기 메시지가 있으면 1분마다 +1 (5개 이상이면 +2), max_count까지
#   줄이기: 대기·처리 중 메시지가 모두 0인 상태가 idle_minutes 동안 이어지면 0으로
# 처리 중인 태스크는 워커가 ECS 태스크 보호를 켜 두므로 축소·배포 때 중간에 끊기지 않는다.
resource "aws_appautoscaling_policy" "queue_out" {
  count              = local.scaled && var.queue_scaling != null ? 1 : 0
  name               = "${var.name}-queue-out"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 5
      scaling_adjustment          = 1
    }
    step_adjustment {
      metric_interval_lower_bound = 5
      scaling_adjustment          = 2
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_out" {
  count               = local.scaled && var.queue_scaling != null ? 1 : 0
  alarm_name          = "${var.name}-queue-backlog"
  alarm_description   = "워커 확장: 대기 중인 작업이 있다"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.queue_scaling.queue_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.queue_out[0].arn]
}

resource "aws_appautoscaling_policy" "queue_in" {
  count              = local.scaled && var.queue_scaling != null ? 1 : 0
  name               = "${var.name}-queue-in"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = var.min_count
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_in" {
  count               = local.scaled && var.queue_scaling != null ? 1 : 0
  alarm_name          = "${var.name}-queue-idle"
  alarm_description   = "워커 축소: 대기·처리 중 작업이 ${var.queue_scaling.idle_minutes}분 동안 없다"
  evaluation_periods  = var.queue_scaling.idle_minutes
  comparison_operator = "LessThanThreshold"
  threshold           = 0.5         # 0개. 0과 같음이 단계 구간 경계에 걸리지 않게 0.5로 둔다
  treat_missing_data  = "breaching" # 지표가 끊긴 빈 큐는 유휴로 본다
  alarm_actions       = [aws_appautoscaling_policy.queue_in[0].arn]

  metric_query {
    id          = "total"
    expression  = "FILL(visible, 0) + FILL(inflight, 0)"
    label       = "visible + in flight"
    return_data = true
  }

  metric_query {
    id = "visible"
    metric {
      namespace   = "AWS/SQS"
      metric_name = "ApproximateNumberOfMessagesVisible"
      dimensions  = { QueueName = var.queue_scaling.queue_name }
      stat        = "Maximum"
      period      = 60
    }
  }

  metric_query {
    id = "inflight"
    metric {
      namespace   = "AWS/SQS"
      metric_name = "ApproximateNumberOfMessagesNotVisible"
      dimensions  = { QueueName = var.queue_scaling.queue_name }
      stat        = "Maximum"
      period      = 60
    }
  }
}
