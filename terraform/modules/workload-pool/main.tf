# Separate workload PostgreSQL pool. Does not initialize SQL registration or create app allocations.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  identifier = "${var.name_prefix}-workload-pool"
  database   = "sky_pool_${var.pool_id}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_security_group" "database" {
  name        = "${local.identifier}-database"
  description = "Shared workload PostgreSQL; no CIDR ingress"
  vpc_id      = var.vpc_id
}

# Future deployed apps use this SG, not the Sky API's SG.
resource "aws_security_group" "runtime" {
  name        = "${local.identifier}-runtime"
  description = "App runtime clients of the registered workload pool"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "database" {
  for_each = {
    allocator = var.allocator_security_group_id
    runtime   = aws_security_group.runtime.id
  }
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "runtime_database" {
  security_group_id            = aws_security_group.runtime.id
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "runtime_https" {
  security_group_id = aws_security_group.runtime.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_db_subnet_group" "this" {
  name       = local.identifier
  subnet_ids = var.data_subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name   = local.identifier
  family = "postgres${split(".", var.engine_version)[0]}"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_kms_key" "app_secrets" {
  description             = "Encryption of app credentials in workload pool ${var.pool_id}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}

resource "aws_db_instance" "this" {
  identifier                      = local.identifier
  engine                          = "postgres"
  engine_version                  = var.engine_version
  instance_class                  = var.instance_class
  db_name                         = local.database
  username                        = "sky_pool_admin"
  manage_master_user_password     = true
  allocated_storage               = 20
  max_allocated_storage           = 100
  storage_type                    = "gp3"
  storage_encrypted               = true
  multi_az                        = var.multi_az
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  parameter_group_name            = aws_db_parameter_group.this.name
  publicly_accessible             = false
  backup_retention_period         = 7
  copy_tags_to_snapshot           = true
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${local.identifier}-final"
  auto_minor_version_upgrade      = true
  apply_immediately               = false
  enabled_cloudwatch_logs_exports = ["postgresql"]
  tags = {
    "sky-managed"       = "true"
    "sky-database-role" = "shared_workload"
    "sky-pool-id"       = var.pool_id
  }
  lifecycle { prevent_destroy = true }
}
