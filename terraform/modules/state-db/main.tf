# [State DB] 서비스 서버 상태 저장소 (A안의 .sky/ JSON 파일을 대체)
# PostgreSQL Multi-AZ. 마스터 비밀번호는 RDS가 Secrets Manager에 만들고 주기적으로 교체한다.
# 교체되므로 태스크에 값을 주입하지 않고, 앱이 비밀 ARN으로 접속할 때마다 읽는다.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  identifier = "${var.name_prefix}-state"
  family     = "postgres${split(".", var.engine_version)[0]}"
}

resource "aws_db_subnet_group" "this" {
  name       = local.identifier
  subnet_ids = var.data_subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name   = local.identifier
  family = local.family

  # TLS가 아닌 접속을 거부한다. PostgreSQL 17은 기본값이 이미 1이지만, 기본값이 바뀌어도 유지되도록 명시한다.
  # apply_method를 지정하지 않으면 AWS가 돌려주는 pending-reboot와 달라 plan마다 차이가 생긴다 (2026-10-10 확인).
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # 1초 넘는 쿼리를 로그로 남긴다.
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier     = local.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name                     = var.database_name
  username                    = var.master_username
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage_gib
  max_allocated_storage = var.max_allocated_storage_gib
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  backup_retention_period   = var.backup_retention_days
  backup_window             = "17:00-18:00" # KST 02:00-03:00
  maintenance_window        = "sun:18:30-sun:19:30"
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.identifier}-final"

  auto_minor_version_upgrade      = true
  apply_immediately               = false
  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    prevent_destroy = true
  }
}
