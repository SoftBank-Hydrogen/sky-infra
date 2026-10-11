# Transport preparation does not enable cutover admission or start a worker.
# Runtime controllers and their evidence must be registered separately.
variable "enable_database_cutover_queue" {
  type    = bool
  default = false
  validation {
    condition     = !var.enable_database_cutover_queue || var.enable_dedicated_preparation
    error_message = "Cutover transport requires registered shared and dedicated database preparation."
  }
}

module "database_cutover_queue" {
  count       = var.enable_database_cutover_queue ? 1 : 0
  source      = "../../modules/queue"
  name_prefix = "${local.name_prefix}-database-cutover"
}

data "aws_iam_policy_document" "database_cutover_publisher" {
  count = var.enable_database_cutover_queue ? 1 : 0
  statement {
    sid       = "PublishOwnedCutoverOperations"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
    resources = [module.database_cutover_queue[0].queue_arn]
  }
}

resource "aws_iam_role_policy" "database_cutover_publisher" {
  count  = var.enable_database_cutover_queue ? 1 : 0
  name   = "${local.name_prefix}-database-cutover-publisher"
  role   = split("/", module.iam.api_task_role_arn)[1]
  policy = data.aws_iam_policy_document.database_cutover_publisher[0].json
}

output "database_cutover_transport" {
  value = var.enable_database_cutover_queue ? {
    queue_url         = module.database_cutover_queue[0].queue_url
    queue_arn         = module.database_cutover_queue[0].queue_arn
    dlq_arn           = module.database_cutover_queue[0].dlq_arn
    queue_name        = module.database_cutover_queue[0].queue_name
    admission_enabled = false
    worker_enabled    = false
  } : null
}
