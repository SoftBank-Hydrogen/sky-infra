variable "name_prefix" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "queue_name" {
  type = string
}

variable "dlq_name" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "http_5xx_threshold" {
  description = "이 건수 이상이면 5xx 알람"
  type        = number
  default     = 10
}

variable "http_5xx_period_seconds" {
  type    = number
  default = 300
}

variable "max_job_wait_minutes" {
  description = "가장 오래된 작업이 이 시간 넘게 대기하면 알람"
  type        = number
  default     = 15
}
