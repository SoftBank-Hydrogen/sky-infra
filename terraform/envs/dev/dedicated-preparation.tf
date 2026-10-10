# Resource preparation and worker activation are intentionally separate switches.
variable "enable_dedicated_preparation" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_dedicated_preparation || (var.enable_shared_workload_pool && length(var.dedicated_target_instance_ids) > 0)
    error_message = "Dedicated preparation requires registered pool and explicit target IDs."
  }
}
variable "dedicated_target_instance_ids" {
  type    = set(string)
  default = []
}
variable "enable_dedicated_worker" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_dedicated_worker || (var.enable_dedicated_preparation && can(regex("^[a-f0-9]{40}$", var.dedicated_worker_image_tag)) && var.dedicated_worker_image_tag == var.platform_image_tag && try(jsondecode(var.dedicated_policies_json).schema_version == 1, false))
    error_message = "Worker requires reviewed policies and compatible immutable worker/outbox platform image."
  }
}
variable "dedicated_worker_image_tag" {
  type    = string
  default = ""
}
variable "dedicated_policies_json" {
  type    = string
  default = ""
}
variable "dedicated_worker_min_count" {
  type    = number
  default = 0
  validation {
    condition     = contains([0, 1], var.dedicated_worker_min_count)
    error_message = "Preparation worker can be paused or run as one task."
  }
}
variable "dedicated_engine_version" {
  type    = string
  default = "17.6"
}
variable "dedicated_instance_class" {
  type    = string
  default = "db.t4g.small"
}
variable "dedicated_storage_gb" {
  type    = number
  default = 20
}
variable "dedicated_multi_az" {
  type    = bool
  default = false
}
resource "aws_security_group" "dedicated_database" {
  count       = var.enable_dedicated_preparation ? 1 : 0
  name        = "${local.name_prefix}-dedicated-database"
  description = "Dedicated workload RDS; registered SG clients only"
  vpc_id      = module.network.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "dedicated_database" {
  for_each = var.enable_dedicated_preparation ? {
    worker  = module.network.worker_security_group_id
    runtime = module.workload_pool[0].runtime_security_group_id
  } : {}
  security_group_id            = aws_security_group.dedicated_database[0].id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_vpc_security_group_egress_rule" "dedicated_runtime" {
  count                        = var.enable_dedicated_preparation ? 1 : 0
  security_group_id            = module.workload_pool[0].runtime_security_group_id
  referenced_security_group_id = aws_security_group.dedicated_database[0].id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_db_subnet_group" "dedicated" {
  count      = var.enable_dedicated_preparation ? 1 : 0
  name       = "${local.name_prefix}-dedicated-database"
  subnet_ids = module.network.data_subnet_ids
}
resource "aws_db_parameter_group" "dedicated" {
  count  = var.enable_dedicated_preparation ? 1 : 0
  name   = "${local.name_prefix}-dedicated-database"
  family = "postgres17"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}
module "dedicated_preparation" {
  count                       = var.enable_dedicated_preparation ? 1 : 0
  source                      = "../../modules/dedicated-preparation"
  name_prefix                 = local.name_prefix
  state_secret_arn            = module.state_db.master_secret_arn
  source_instance_id          = module.workload_pool[0].registration.settings.pool.instance_id
  target_instance_ids         = var.dedicated_target_instance_ids
  subnet_group                = aws_db_subnet_group.dedicated[0].name
  parameter_group             = aws_db_parameter_group.dedicated[0].name
  create_permissions_boundary = true
  cluster_name                = local.cluster_name
}
locals {
  dedicated_configuration = var.enable_dedicated_preparation ? {
    version = 1
    settings = {
      database_security_group = aws_security_group.dedicated_database[0].id
      subnet_group            = aws_db_subnet_group.dedicated[0].name
      parameter_group         = aws_db_parameter_group.dedicated[0].name
      instance_class          = var.dedicated_instance_class
      engine_version          = var.dedicated_engine_version
      storage_gb              = var.dedicated_storage_gb
      multi_az                = var.dedicated_multi_az
    }
  } : null
}
resource "aws_cloudwatch_log_group" "dedicated" {
  count             = var.enable_dedicated_worker ? 1 : 0
  name              = "/${local.name_prefix}/dedicated-preparation"
  retention_in_days = 14
}
resource "aws_iam_role" "dedicated_execution" {
  count              = var.enable_dedicated_worker ? 1 : 0
  name               = "${local.name_prefix}-dedicated-preparation-execution"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.amazonaws.com" }, Condition = { StringEquals = { "aws:SourceAccount" = var.aws_account_id } } }] })
}
resource "aws_iam_role_policy" "dedicated_execution" {
  count = var.enable_dedicated_worker ? 1 : 0
  role  = aws_iam_role.dedicated_execution[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = module.ecr.repository_arn },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.dedicated[0].arn}:*" },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [module.secrets.secret_arns["alb-trusts"], module.secrets.secret_arns["memberships"]] }
  ] })
}
module "dedicated_worker" {
  count                  = var.enable_dedicated_worker ? 1 : 0
  source                 = "../../modules/ecs-service"
  name                   = "${local.name_prefix}-dedicated-preparation"
  cluster_arn            = module.cluster.cluster_arn
  image                  = "${module.ecr.repository_url}:${var.dedicated_worker_image_tag}"
  command                = ["worker", "--mode", "dedicated-database-queue"]
  cpu                    = 256
  memory                 = 512
  execution_role_arn     = aws_iam_role.dedicated_execution[0].arn
  task_role_arn          = module.dedicated_preparation[0].task_role_arn
  subnet_ids             = module.network.app_subnet_ids
  security_group_id      = module.network.worker_security_group_id
  min_count              = var.dedicated_worker_min_count
  max_count              = 1
  enable_execute_command = false
  stop_timeout_seconds   = 120
  environment = merge(local.common_environment, {
    SKY_STATE_WORKSPACE                = var.allocation_worker_workspace
    SKY_SHARED_DATABASE_POOL_JSON      = jsonencode(module.workload_pool[0].registration)
    SKY_DEDICATED_DATABASE_CONFIG_JSON = jsonencode(local.dedicated_configuration)
    SKY_OPERATING_REVIEW_POLICIES_JSON = var.dedicated_policies_json
    SKY_DEDICATED_DATABASE_QUEUE_URL   = module.dedicated_preparation[0].queue_url
    SKY_DEDICATED_TASK_PROTECTION      = "required"
  })
  secrets           = { SKY_ALB_TRUSTS_JSON = module.secrets.secret_arns["alb-trusts"], SKY_MEMBERSHIPS_JSON = module.secrets.secret_arns["memberships"] }
  log_group_name    = aws_cloudwatch_log_group.dedicated[0].name
  log_stream_prefix = "dedicated"
  depends_on        = [aws_iam_role_policy.dedicated_execution, module.cluster]
}
resource "aws_iam_role_policy" "dedicated_publisher" {
  count  = var.enable_dedicated_worker ? 1 : 0
  role   = split("/", module.iam.api_task_role_arn)[1]
  policy = module.dedicated_preparation[0].publisher_policy_json
}
output "dedicated_preparation" {
  value = var.enable_dedicated_preparation ? {
    queue_url     = module.dedicated_preparation[0].queue_url
    task_role_arn = module.dedicated_preparation[0].task_role_arn
    configuration = local.dedicated_configuration
  } : null
}
