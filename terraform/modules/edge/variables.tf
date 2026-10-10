variable "name_prefix" {
  type = string
}

variable "zone_name" {
  description = "Route 53 퍼블릭 호스팅 영역. 이 모듈은 읽기만"
  type        = string
}

variable "service_domain" {
  description = "서비스 주소. zone_name 아래여야 한다"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  description = "API 태스크 헬스 체크 경로. DB 연결까지 확인하는 가벼운 엔드포인트여야 한다"
  type        = string
  default     = "/health"
}

variable "enable_auth" {
  description = "ALB 앞단 Cognito 로그인. 끄면 누구나 Sky에 접근할 수 있다"
  type        = bool
  default     = true
}

variable "cognito_domain_prefix" {
  description = "Cognito 기본 도메인 접두어. null이면 이름 접두어와 계정 해시로 만든다"
  type        = string
  default     = null
}
