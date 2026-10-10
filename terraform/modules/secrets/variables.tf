variable "name_prefix" {
  type = string
}

variable "secrets" {
  description = "비밀 키(이름 뒷부분) → 설명"
  type        = map(string)
  default = {
    "openai-api-key"          = "Sky가 앱 분석에 쓰는 OpenAI API 키 (OPENAI_API_KEY)"
    "gcp-service-account-key" = "Sky가 Cloud Run 배포에 쓰는 GCP 서비스 계정 키 JSON"
    "github-app-private-key"  = "Sky GitHub App 개인 키 PEM. 소스 폴링과 빌드 워크플로 실행에 쓴다"
    "alb-trusts"              = "API가 신뢰하는 ALB 로그인 설정 JSON (SKY_ALB_TRUSTS_JSON)"
    "memberships"             = "API 사용자 조직·역할 JSON (SKY_MEMBERSHIPS_JSON). 바꾸면 API 서비스를 다시 배포한다"
  }
}
