variable "name_prefix" {
  type = string
}

variable "build_retention_days" {
  description = "sources/, builds/ 보관 일수. 배포 기록(records/)은 지우지 않는다"
  type        = number
  default     = 30
}

variable "noncurrent_version_days" {
  description = "덮어쓰거나 지운 객체의 이전 버전 보관 일수"
  type        = number
  default     = 30
}
