output "task_role_arn" { value = aws_iam_role.task.arn }
output "queue_url" { value = module.queue.queue_url }
output "queue_arn" { value = module.queue.queue_arn }
output "dlq_arn" { value = module.queue.dlq_arn }
output "task_policy_json" { value = jsonencode(local.task_policy) }
output "publisher_policy_json" {
  value = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["sqs:SendMessage", "sqs:GetQueueAttributes"], Resource = [module.queue.queue_arn] }] })
}
