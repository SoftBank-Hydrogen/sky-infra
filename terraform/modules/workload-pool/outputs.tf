output "registration" {
  description = "Public identity/reference configuration; no credentials. Must be initialized from an authorized VPC worker."
  value = {
    version = 1
    settings = {
      pool = {
        id                = var.pool_id
        account_id        = data.aws_caller_identity.current.account_id
        region            = data.aws_region.current.region
        instance_id       = aws_db_instance.this.identifier
        control_database  = aws_db_instance.this.db_name
        connection_budget = var.connection_budget
        role              = "shared_workload"
      }
      resource_id             = aws_db_instance.this.resource_id
      vpc_id                  = var.vpc_id
      database_security_group = aws_security_group.database.id
      allowed_client_groups   = [var.allocator_security_group_id, aws_security_group.runtime.id]
      admin_secret_arn        = one(aws_db_instance.this.master_user_secret[*].secret_arn)
      app_secret_kms_arn      = aws_kms_key.app_secrets.arn
      sslrootcert             = "/etc/ssl/certs/sky-rds-global-bundle.pem"
    }
  }
}
output "runtime_security_group_id" {
  value = aws_security_group.runtime.id
}
output "identifier" {
  value = aws_db_instance.this.identifier
}
