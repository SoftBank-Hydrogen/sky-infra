variable "repository_name" {
  type    = string
  default = "sky-platform"
}

variable "keep_images" {
  description = "보관할 최근 이미지 수"
  type        = number
  default     = 20
}
