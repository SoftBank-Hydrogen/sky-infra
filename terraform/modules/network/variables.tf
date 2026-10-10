variable "name_prefix" {
  description = "리소스 이름 접두어 (예: sky-dev)"
  type        = string
}

variable "cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "AZ → 퍼블릭 서브넷 CIDR (ALB, NAT)"
  type        = map(string)
  default = {
    "ap-northeast-2a" = "10.0.0.0/24"
    "ap-northeast-2c" = "10.0.1.0/24"
  }
}

variable "app_subnet_cidrs" {
  description = "AZ → 앱 서브넷 CIDR"
  type        = map(string)
  default = {
    "ap-northeast-2a" = "10.0.10.0/24"
    "ap-northeast-2c" = "10.0.11.0/24"
  }
}

variable "data_subnet_cidrs" {
  description = "AZ → 데이터 서브넷 CIDR"
  type        = map(string)
  default = {
    "ap-northeast-2a" = "10.0.20.0/24"
    "ap-northeast-2c" = "10.0.21.0/24"
  }
}

variable "app_port" {
  description = "ALB가 앱 태스크로 보내는 포트"
  type        = number
  default     = 8080
}
