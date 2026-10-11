variable "name_prefix" { type = string }
variable "cluster_arn" { type = string }
variable "cluster_name" { type = string }
variable "image" { type = string }
variable "platform_repository_arn" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "queue_url" { type = string }
variable "queue_arn" { type = string }
variable "registration" { type = any }
variable "environment" { type = map(string) }
variable "state_secret_arn" { type = string }
variable "identity_secrets" { type = map(string) }

variable "min_count" {
  type    = number
  default = 1
  validation {
    condition     = contains([0, 1], var.min_count)
    error_message = "Allocator can be paused or run as one task."
  }
}
