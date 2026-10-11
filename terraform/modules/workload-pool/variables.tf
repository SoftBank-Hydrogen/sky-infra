variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "data_subnet_ids" { type = list(string) }
variable "allocator_security_group_id" { type = string }
variable "pool_id" {
  type    = string
  default = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,31}$", var.pool_id))
    error_message = "pool_id must be a lowercase SQL-safe identifier of at most 32 characters."
  }
}
variable "instance_class" {
  type    = string
  default = "db.t4g.small"
}
variable "engine_version" {
  type    = string
  default = "17"
}
variable "multi_az" {
  type    = bool
  default = false
}
variable "connection_budget" {
  type    = number
  default = 30
  validation {
    condition     = var.connection_budget == floor(var.connection_budget) && var.connection_budget >= 1 && var.connection_budget <= 1000
    error_message = "connection_budget must be an integer between 1 and 1000."
  }
}
