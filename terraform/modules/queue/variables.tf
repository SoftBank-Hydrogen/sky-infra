variable "name_prefix" {
  type = string
}

variable "visibility_timeout_seconds" {
  description = "처음 받은 뒤 다른 워커에게 보이지 않는 시간. 워커는 처리 중 주기적으로 늘린다"
  type        = number
  default     = 300
}

variable "message_retention_seconds" {
  type    = number
  default = 345600 # 4일
}

variable "max_receive_count" {
  description = "이 횟수만큼 받고도 지워지지 않으면 DLQ로 보낸다 (워커가 죽은 경우 포함)"
  type        = number
  default     = 3
}
