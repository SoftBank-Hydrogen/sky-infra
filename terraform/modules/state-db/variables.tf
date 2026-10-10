variable "name_prefix" {
  type = string
}

variable "data_subnet_ids" {
  description = "인터넷 경로가 없는 데이터 서브넷 (2개 AZ)"
  type        = list(string)
}

variable "security_group_id" {
  description = "API·워커 태스크에서만 5432를 허용하는 보안 그룹"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL 메이저 또는 메이저.마이너 버전. 파라미터 그룹 계열을 여기서 정한다"
  type        = string
  default     = "17"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "multi_az" {
  description = "B안 기본값 true. 비용을 줄이려고 dev에서 끌 때만 false"
  type        = bool
  default     = true
}

variable "database_name" {
  type    = string
  default = "sky"
}

variable "master_username" {
  type    = string
  default = "sky_admin"
}

variable "allocated_storage_gib" {
  type    = number
  default = 20
}

variable "max_allocated_storage_gib" {
  description = "스토리지 자동 확장 상한"
  type        = number
  default     = 100
}

variable "backup_retention_days" {
  type    = number
  default = 14
}
