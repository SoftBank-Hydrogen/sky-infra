variable "name_prefix" {
  type = string
}

variable "services" {
  description = "서비스 키(api, worker, outbox) → 실행 역할이 주입할 비밀 ARN 목록"
  type = map(object({
    secret_arns = list(string)
  }))

  validation {
    condition     = toset(keys(var.services)) == toset(["api", "worker", "outbox"])
    error_message = "services 키는 api, worker, outbox 세 개여야 한다."
  }
}

variable "log_group_names" {
  description = "서비스 키 → 앱 로그 그룹 이름"
  type        = map(string)
}

variable "exec_log_group_name" {
  description = "ECS Exec 세션 기록 로그 그룹 이름"
  type        = string
}

variable "platform_repository_arn" {
  description = "서비스 서버 이미지 ECR 레포(sky-platform) ARN"
  type        = string
}

variable "platform_secret_arns" {
  description = "sky-infra가 만든 비밀 전체 ARN (이미지 배포 역할이 메타데이터를 refresh)"
  type        = list(string)
}

variable "state_db_secret_arn" {
  description = "상태 DB 마스터 비밀 ARN (RDS 관리)"
  type        = string
}

variable "artifacts_bucket_arn" {
  type = string
}

variable "queue_arn" {
  description = "작업 큐 ARN"
  type        = string
}

variable "cluster_name" {
  description = "서비스 서버 ECS 클러스터 이름"
  type        = string
}

variable "service_names" {
  description = "서비스 키 → ECS 서비스 이름 (= 태스크 정의 계열 이름)"
  type        = map(string)
}

variable "state_bucket_name" {
  description = "Terraform state 버킷 (이미지 배포 역할 범위)"
  type        = string
}

variable "state_key" {
  description = "이 환경 state 객체 키 (이미지 배포 역할 범위)"
  type        = string
}

variable "shared_database_queue_arns" {
  description = "Dedicated shared DB allocation queues; publisher sends, worker consumes. No DLQ redrive permission."
  type        = list(string)
  default     = []
}
