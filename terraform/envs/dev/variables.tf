variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "aws_account_id" {
  description = "대상 AWS 계정 ID. tfvars(로컬) 또는 TF_VAR_aws_account_id(CI)로만 넘긴다"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "12자리 AWS 계정 ID여야 한다."
  }
}

variable "github_org" {
  type    = string
  default = "SoftBank-Hydrogen"
}

variable "create_github_oidc_provider" {
  description = "계정에 GitHub OIDC 공급자가 이미 있으면 false"
  type        = bool
  default     = true
}

variable "infra_apply_policy_arns" {
  description = "apply 역할에 붙일 정책 ARN 목록"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# 앞단
# ---------------------------------------------------------------------------

variable "zone_name" {
  description = "콘솔에서 만든 Route 53 호스팅 영역. Terraform은 읽기만 한다"
  type        = string
  default     = "cloudas.store"
}

variable "service_domain" {
  description = "Sky 서비스 주소"
  type        = string
  default     = "cloudas.store"
}

variable "health_check_path" {
  description = "ALB 헬스 체크 경로. sky-platform 서비스 이미지의 /health (프로세스 생존만 확인)"
  type        = string
  default     = "/health"
}

variable "enable_auth" {
  description = "ALB 앞단 Cognito 로그인. 인터넷에 열리므로 끄지 않는다"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# 서비스 서버 이미지와 컴퓨트
# ---------------------------------------------------------------------------

variable "platform_image_tag" {
  description = "서비스 서버 이미지 태그(sky-platform 커밋의 7자리 git SHA). platform-image.auto.tfvars에서만 바꾼다"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7}$", var.platform_image_tag))
    error_message = "platform_image_tag는 7자리 소문자 git SHA여야 한다."
  }
}

variable "api_command" {
  description = "API 컨테이너 명령. null이면 이미지 기본값(웹 서버)"
  type        = list(string)
  default     = null
}

variable "worker_command" {
  description = "워커 컨테이너 명령. 이미지 ENTRYPOINT(sky-service) 뒤에 붙는 인자다"
  type        = list(string)
  default     = ["worker"]
}

variable "api_cpu" {
  type    = number
  default = 512
}

variable "api_memory" {
  type    = number
  default = 1024
}

variable "api_min_count" {
  description = "AZ 2개에 하나씩. 배포·장애 중에도 하나는 남는다"
  type        = number
  default     = 2
}

variable "api_max_count" {
  type    = number
  default = 4
}

variable "api_requests_per_target" {
  description = "태스크 하나가 1분에 받을 ALB 요청 수 목표"
  type        = number
  default     = 300
}

variable "worker_cpu" {
  type    = number
  default = 1024
}

variable "worker_memory" {
  type    = number
  default = 2048
}

variable "worker_max_count" {
  description = "동시에 처리할 작업 수 상한 (태스크 하나가 작업 하나)"
  type        = number
  default     = 3
}

variable "worker_idle_minutes" {
  description = "작업이 없는 상태가 이만큼 이어지면 워커를 0으로 줄인다"
  type        = number
  default     = 10
}

# ---------------------------------------------------------------------------
# 상태 DB
# ---------------------------------------------------------------------------

variable "state_db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "state_db_multi_az" {
  description = "B안 기본값 true"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# 사용자 앱 빌드 (GitHub Actions)
# ---------------------------------------------------------------------------

variable "builder_repository" {
  description = "사용자 앱 빌드 워크플로가 있는 저장소 이름 (github_org 아래)"
  type        = string
  default     = "sky-builder"
}

variable "builder_workflow" {
  description = "워커가 workflow_dispatch로 실행할 워크플로 파일 이름"
  type        = string
  default     = "build.yaml"
}

variable "github_app_id" {
  description = "Sky GitHub App ID (비밀 아님). 개인 키는 Secrets Manager github-app-private-key"
  type        = string
  default     = ""
}
