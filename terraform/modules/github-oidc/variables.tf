variable "name_prefix" {
  type = string
}

variable "create_provider" {
  description = "계정에 GitHub OIDC 공급자가 아직 없으면 true"
  type        = bool
  default     = true
}

variable "permissions_boundary_arn" {
  description = "모든 역할에 걸 권한 경계. 없으면 null"
  type        = string
  default     = null
}

variable "roles" {
  description = "역할 이름(접두어 제외) → 신뢰 조건과 권한"
  type = map(object({
    description         = string
    subjects            = list(string)
    managed_policy_arns = optional(list(string), [])
    max_session_seconds = optional(number, 3600)
  }))

  validation {
    condition = alltrue([
      for cfg in values(var.roles) : alltrue([
        for s in cfg.subjects : startswith(s, "repo:") && !contains(["repo:*", "repo:*/*"], s)
      ])
    ])
    error_message = "subjects는 repo:<org>/<repo>:... 또는 repo:<org>@<id>/<repo>@<id>:... 형식이어야 하고, 모든 저장소를 허용하는 와일드카드는 쓸 수 없다."
  }
}

# 정책 JSON은 다른 자원 ARN을 참조해 plan 시점에 unknown일 수 있다.
# for_each 키는 이 map의 키(역할 이름)로만 정해지므로 키는 반드시 정적인 값으로 쓴다.
variable "inline_policies" {
  description = "역할 이름(접두어 제외) → 인라인 정책 JSON"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for role in keys(var.inline_policies) : contains(keys(var.roles), role)])
    error_message = "inline_policies의 키는 roles에 있는 역할 이름이어야 한다."
  }
}
