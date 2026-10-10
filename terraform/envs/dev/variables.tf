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

# 이 조직은 GitHub Actions OIDC sub에 이름 대신 변경 불가능한 조직·저장소 ID를 넣는다.
# 저장소를 새로 만들면 GitHub REST API의 repository id와 OIDC subject template을 확인해 갱신한다.
variable "github_org_id" {
  type    = string
  default = "338183202"
  validation {
    condition     = can(regex("^[0-9]+$", var.github_org_id))
    error_message = "github_org_id는 GitHub 조직의 숫자 ID여야 한다."
  }
}

variable "github_infra_repository_id" {
  type    = string
  default = "1412003322"
  validation {
    condition     = can(regex("^[0-9]+$", var.github_infra_repository_id))
    error_message = "github_infra_repository_id는 GitHub 저장소의 숫자 ID여야 한다."
  }
}

variable "github_platform_repository_id" {
  type    = string
  default = "1407769237"
  validation {
    condition     = can(regex("^[0-9]+$", var.github_platform_repository_id))
    error_message = "github_platform_repository_id는 GitHub 저장소의 숫자 ID여야 한다."
  }
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
  description = "ALB 헬스 체크 경로. sky-platform API의 /ready (DB 연결·스키마 확인, 준비 전이면 503). 프로세스 생존만 보려면 /health"
  type        = string
  default     = "/ready"
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
  description = "API 컨테이너 명령. 이미지 ENTRYPOINT(sky-service) 뒤에 붙는 인자다. preparation(업로드·미리보기·승인·접수)을 켠다. --origin은 서비스 URL과 같아야 하고, 켜기 전에 migrate로 admission/approval/preview 스키마를 적용해 둬야 한다"
  type        = list(string)
  default     = ["api", "--enable-preparation", "--origin", "https://cloudas.store"]
}

variable "worker_command" {
  description = "워커 컨테이너 명령. 이미지 ENTRYPOINT(sky-service) 뒤에 붙는 인자다"
  type        = list(string)
  default     = ["worker", "--mode", "build", "--deploy-built-image"]
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

variable "github_builder_repository_id" {
  description = "sky-builder의 GitHub 저장소 숫자 ID. 저장소 생성 전에는 빈 값으로 두어 OIDC 역할을 만들지 않는다."
  type        = string
  default     = ""
  validation {
    condition     = var.github_builder_repository_id == "" || can(regex("^[0-9]+$", var.github_builder_repository_id))
    error_message = "github_builder_repository_id는 빈 값 또는 GitHub 저장소의 숫자 ID여야 한다."
  }
}

variable "builder_workflow" {
  description = "워커가 workflow_dispatch로 실행할 워크플로 파일 이름"
  type        = string
  default     = "build.yml"
}

variable "github_app_id" {
  description = "Sky GitHub App ID (비밀 아님). 개인 키는 Secrets Manager github-app-private-key"
  type        = string
  default     = ""
}

# 원격 빌드 전용 App. API의 소스 감시 App과 별도로 설정한다.
variable "github_builder_app_id" {
  description = "sky-builder dispatch GitHub App ID (비밀 아님)"
  type        = string
  default     = ""
  validation {
    condition     = var.github_builder_app_id == "" || can(regex("^[0-9]{1,20}$", var.github_builder_app_id))
    error_message = "github_builder_app_id는 빈 값 또는 숫자 ID여야 한다."
  }
}

variable "github_builder_installation_id" {
  description = "sky-builder App의 조직 installation ID (Client ID 아님)"
  type        = string
  default     = ""
  validation {
    condition     = var.github_builder_installation_id == "" || can(regex("^[0-9]{1,20}$", var.github_builder_installation_id))
    error_message = "github_builder_installation_id는 빈 값 또는 숫자 ID여야 한다."
  }
}

variable "builder_ref" {
  description = "고정된 workflow commit을 가리키는 builder ref"
  type        = string
  default     = "main"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.builder_ref))
    error_message = "builder_ref는 현재 플랫폼이 지원하는 단일 ref 이름이어야 한다."
  }
}

variable "builder_code_sha" {
  description = "검토된 builder workflow의 전체 40자리 commit SHA"
  type        = string
  default     = ""
  validation {
    condition     = var.builder_code_sha == "" || can(regex("^[0-9a-f]{40}$", var.builder_code_sha))
    error_message = "builder_code_sha는 빈 값 또는 40자리 소문자 SHA여야 한다."
  }
}

variable "builder_platform_code_sha" {
  description = "builder가 checkout하는 플랫폼 코드의 전체 40자리 SHA. builder repository variable과 같아야 한다"
  type        = string
  default     = ""
  validation {
    condition     = var.builder_platform_code_sha == "" || can(regex("^[0-9a-f]{40}$", var.builder_platform_code_sha))
    error_message = "builder_platform_code_sha는 빈 값 또는 40자리 소문자 SHA여야 한다."
  }
}
