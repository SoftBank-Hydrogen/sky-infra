variable "name_prefix" {
  type = string
}
variable "state_secret_arn" {
  type = string
}
variable "source_instance_id" {
  type = string
}
variable "target_instance_ids" {
  type = set(string)
  validation {
    condition     = length(var.target_instance_ids) > 0 && alltrue([for id in var.target_instance_ids : can(regex("^sky-[a-z][a-z0-9-]{2,55}$", id)) && id != var.source_instance_id])
    error_message = "Register explicit distinct target identifiers."
  }
}
variable "subnet_group" {
  type = string
}
variable "parameter_group" {
  type = string
}
variable "permissions_boundary_arn" {
  type    = string
  default = null
  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:policy/.+", var.permissions_boundary_arn))
    error_message = "A pre-existing task permission boundary is required."
  }
}
variable "create_permissions_boundary" {
  type    = bool
  default = false
}
variable "cluster_name" {
  type    = string
  default = ""
}
