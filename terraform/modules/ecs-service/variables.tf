variable "name" {
  description = "서비스와 태스크 정의 계열 이름 (예: sky-dev-api)"
  type        = string
}

variable "cluster_arn" {
  type = string
}

variable "image" {
  description = "컨테이너 이미지 (<ECR URL>:<git SHA>)"
  type        = string
}

variable "command" {
  description = "컨테이너 명령. null이면 이미지 기본값"
  type        = list(string)
  default     = null
}

variable "container_port" {
  description = "ALB가 보내는 포트. 워커처럼 받지 않으면 null"
  type        = number
  default     = null
}

variable "cpu" {
  type = number
}

variable "memory" {
  description = "MiB"
  type        = number
}

variable "ephemeral_storage_gib" {
  description = "Fargate 임시 스토리지 (21~200). 소스 스냅샷을 다루는 워커는 늘린다"
  type        = number
  default     = 21
}

variable "stop_timeout_seconds" {
  description = "SIGTERM 후 SIGKILL까지 대기 시간. Fargate 최대 120"
  type        = number
  default     = 30
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "target_group_arn" {
  description = "ALB 대상 그룹. 없으면 null"
  type        = string
  default     = null
}

variable "capacity_provider" {
  description = "FARGATE 또는 FARGATE_SPOT. 작업 중단을 견디지 못하면 FARGATE"
  type        = string
  default     = "FARGATE"
}

variable "min_count" {
  type = number
}

variable "max_count" {
  type = number
}

variable "deployment_minimum_healthy_percent" {
  description = "API는 100(무중단). 워커는 태스크 보호로 작업을 지키므로 0도 된다"
  type        = number
  default     = 100
}

variable "request_scaling" {
  description = "ALB 대상당 요청 수 대상 추적. resource_label은 <ALB ARN 접미사>/<대상 그룹 ARN 접미사>"
  type = object({
    resource_label      = string
    requests_per_target = number
  })
  default = null
}

variable "cpu_target_percent" {
  description = "평균 CPU 대상 추적. 없으면 null"
  type        = number
  default     = null
}

variable "queue_scaling" {
  description = "SQS 큐 길이 단계 조정 (0~N)"
  type = object({
    queue_name   = string
    idle_minutes = number
  })
  default = null
}

variable "environment" {
  description = "컨테이너 환경변수 (비밀이 아닌 값)"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "환경변수 이름 → Secrets Manager ARN (실행 역할이 읽을 수 있어야 한다)"
  type        = map(string)
  default     = {}
}

variable "log_group_name" {
  type = string
}

variable "log_stream_prefix" {
  type = string
}

variable "depends_on_ids" {
  description = "서비스 생성 전에 끝나야 하는 자원 ID (리스너, 용량 공급자 등). 순서 맞추기에만 쓴다"
  type        = list(string)
  default     = []
}

variable "enable_execute_command" {
  type    = bool
  default = true
}
