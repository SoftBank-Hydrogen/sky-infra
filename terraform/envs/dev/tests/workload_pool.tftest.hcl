mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-2" }
  }
}

run "isolated_workload_pool" {
  command = plan
  module {
    source = "../../modules/workload-pool"
  }
  variables {
    name_prefix                 = "sky-dev"
    vpc_id                      = "vpc-11111111"
    data_subnet_ids             = ["subnet-11111111", "subnet-22222222"]
    allocator_security_group_id = "sg-11111111"
  }
  assert {
    condition = (
      aws_db_instance.this.identifier == "sky-dev-workload-pool" &&
      aws_db_instance.this.db_name == "sky_pool_dev" &&
      aws_db_instance.this.tags["sky-database-role"] == "shared_workload" &&
      aws_db_instance.this.tags["sky-managed"] == "true" &&
      aws_db_instance.this.tags["sky-pool-id"] == "dev"
    )
    error_message = "RDS identity and tags must match the allocator ownership contract."
  }
  assert {
    condition = (
      !aws_db_instance.this.publicly_accessible &&
      aws_db_instance.this.storage_encrypted &&
      aws_db_instance.this.manage_master_user_password &&
      aws_db_instance.this.deletion_protection &&
      !aws_db_instance.this.skip_final_snapshot &&
      length(aws_db_instance.this.vpc_security_group_ids) == 1
    )
    error_message = "Workload RDS must be private, encrypted, managed-secret and deletion protected."
  }
  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.database) == 2 &&
      aws_vpc_security_group_ingress_rule.database["allocator"].referenced_security_group_id == "sg-11111111" &&
      aws_vpc_security_group_ingress_rule.database["allocator"].from_port == 5432 &&
      aws_vpc_security_group_ingress_rule.database["runtime"].to_port == 5432
    )
    error_message = "Only allocator and dedicated app runtime groups may reach PostgreSQL."
  }
  assert {
    condition     = output.registration.settings.pool.control_database == "sky_pool_dev" && output.registration.version == 1
    error_message = "Registration must use the versioned platform pool contract."
  }
  assert {
    condition     = contains([for p in aws_db_parameter_group.this.parameter : "${p.name}=${p.value}"], "rds.force_ssl=1") && aws_kms_key.app_secrets.enable_key_rotation
    error_message = "TLS and app secret key rotation must be enabled."
  }
}
