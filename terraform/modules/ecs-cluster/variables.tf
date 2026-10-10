variable "cluster_name" {
  type = string
}

variable "exec_log_group_name" {
  description = "ECS Exec 세션 기록 로그 그룹"
  type        = string
}
