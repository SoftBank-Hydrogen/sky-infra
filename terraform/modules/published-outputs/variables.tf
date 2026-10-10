variable "namespace" {
  type    = string
  default = "sky"
}

variable "environment" {
  type = string
}

variable "contract_version" {
  description = "출력값 계약 버전"
  type        = number
}

variable "values" {
  description = "키(예: aws/region) → 값. 비밀값은 넣지 않는다"
  type        = map(string)

  validation {
    condition     = alltrue([for k in keys(var.values) : can(regex("^(aws|gcp|onprem)/[a-z0-9_]+$", k))])
    error_message = "키는 <aws|gcp|onprem>/<snake_case> 형식이어야 한다."
  }
}
