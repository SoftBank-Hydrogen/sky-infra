# 개발 환경 main.tf (B안: Fargate API + 워커, RDS·S3·SQS)
# 구조와 결정 근거는 docs/design-b.md를 본다.

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # 값은 backend.hcl로 넘긴다: terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id] # 다른 계정 자격 증명으로는 실행되지 않도록
  default_tags {
    tags = {
      "sky:managed-by"  = "sky-infra"
      "sky:environment" = local.environment
    }
  }
}

locals {
  environment = "dev"
  org         = var.github_org
  name_prefix = "sky-${local.environment}"
  app_port    = 8080

  infra_oidc_subject_prefix    = "repo:${local.org}@${var.github_org_id}/sky-infra@${var.github_infra_repository_id}"
  platform_oidc_subject_prefix = "repo:${local.org}@${var.github_org_id}/sky-platform@${var.github_platform_repository_id}"
  builder_oidc_subject_prefix  = "repo:${local.org}@${var.github_org_id}/${var.builder_repository}@${var.github_builder_repository_id}"

  cluster_name = local.name_prefix
  service_names = {
    api    = "${local.name_prefix}-api"
    worker = "${local.name_prefix}-worker"
    outbox = "${local.name_prefix}-outbox"
  }
  image = "${module.ecr.repository_url}:${var.platform_image_tag}"

  # bootstrap/이 만드는 버킷 이름 규칙과 같다. 키는 backend.hcl과 CI의 key와 같아야 한다.
  state_bucket_name = "sky-tfstate-${var.aws_account_id}-${var.region}"
  state_key         = "envs/${local.environment}/terraform.tfstate"

  # sky-platform이 API·워커 공통으로 읽는 설정 (docs/design-b.md 7장 계약)
  common_environment = {
    SKY_ENVIRONMENT         = local.environment
    SKY_AWS_REGION          = var.region
    SKY_AWS_ACCOUNT_ID      = var.aws_account_id
    SKY_PUBLIC_URL          = module.edge.service_url
    SKY_DATABASE_HOST       = module.state_db.address
    SKY_DATABASE_PORT       = tostring(module.state_db.port)
    SKY_DATABASE_NAME       = module.state_db.database_name
    SKY_DATABASE_SECRET_ARN = module.state_db.master_secret_arn
    SKY_ARTIFACTS_BUCKET    = module.artifacts.bucket_name
    SKY_JOB_QUEUE_URL       = module.queue.queue_url
    SKY_GITHUB_APP_ID       = var.github_app_id
  }

  # 서비스별로 주입하는 비밀. 실행 역할은 여기 있는 비밀만 읽을 수 있다.
  service_secrets = {
    api = {
      SKY_ALB_TRUSTS_JSON        = module.secrets.secret_arns["alb-trusts"]
      SKY_MEMBERSHIPS_JSON       = module.secrets.secret_arns["memberships"]
      SKY_GITHUB_APP_PRIVATE_KEY = module.secrets.secret_arns["github-app-private-key"]
    }
    worker = {
      OPENAI_API_KEY              = module.secrets.secret_arns["openai-api-key"]
      SKY_GCP_SERVICE_ACCOUNT_KEY = module.secrets.secret_arns["gcp-service-account-key"]
      SKY_GITHUB_APP_PRIVATE_KEY  = module.secrets.secret_arns["github-app-private-key"]
    }
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# 네트워크·앞단
# ---------------------------------------------------------------------------

module "network" {
  source      = "../../modules/network"
  name_prefix = local.name_prefix
  app_port    = local.app_port
}

module "edge" {
  source                = "../../modules/edge"
  name_prefix           = local.name_prefix
  zone_name             = var.zone_name
  service_domain        = var.service_domain
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  app_port              = local.app_port
  health_check_path     = var.health_check_path
  enable_auth           = var.enable_auth
}

# ---------------------------------------------------------------------------
# 상태·파일·작업 큐 (A안의 .sky/ 디렉터리와 프로세스 내 스레드를 대체)
# ---------------------------------------------------------------------------

module "state_db" {
  source            = "../../modules/state-db"
  name_prefix       = local.name_prefix
  data_subnet_ids   = module.network.data_subnet_ids
  security_group_id = module.network.data_security_group_id
  instance_class    = var.state_db_instance_class
  multi_az          = var.state_db_multi_az
}

module "artifacts" {
  source      = "../../modules/artifacts"
  name_prefix = local.name_prefix
}

module "queue" {
  source      = "../../modules/queue"
  name_prefix = local.name_prefix
}

# ---------------------------------------------------------------------------
# 이미지·비밀·권한
# ---------------------------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"
}

module "secrets" {
  source      = "../../modules/secrets"
  name_prefix = local.name_prefix
}

module "iam" {
  source      = "../../modules/iam"
  name_prefix = local.name_prefix
  services = {
    api    = { secret_arns = values(local.service_secrets.api) }
    worker = { secret_arns = values(local.service_secrets.worker) }
    outbox = { secret_arns = [] } # 앱 비밀 없음. DB 비밀은 태스크 역할(API)로 직접 읽는다
  }
  log_group_names         = module.observability.log_group_names
  exec_log_group_name     = module.observability.exec_log_group_name
  platform_repository_arn = module.ecr.repository_arn
  platform_secret_arns    = values(module.secrets.secret_arns)
  state_db_secret_arn     = module.state_db.master_secret_arn
  artifacts_bucket_arn    = module.artifacts.bucket_arn
  queue_arn               = module.queue.queue_arn
  cluster_name            = local.cluster_name
  service_names           = local.service_names
  state_bucket_name       = local.state_bucket_name
  state_key               = local.state_key
}

module "github_oidc" {
  source          = "../../modules/github-oidc"
  name_prefix     = local.name_prefix
  create_provider = var.create_github_oidc_provider

  roles = merge({
    # PR에서 plan만 한다. 읽기 전용.
    infra-plan = {
      description         = "sky-infra PR plan (read-only)"
      subjects            = ["${local.infra_oidc_subject_prefix}:pull_request"]
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
    # main 반영 후 GitHub environment 승인을 거친 작업만 apply한다.
    infra-apply = {
      description         = "sky-infra apply (environment-gated)"
      subjects            = ["${local.infra_oidc_subject_prefix}:environment:${local.environment}"]
      managed_policy_arns = var.infra_apply_policy_arns
    }
    # sky-platform ci.yml의 publish-service job이 서비스 서버 이미지를 ECR에 push만 한다.
    # job에 environment: dev가 걸려 있어 sub가 environment:dev가 된다.
    # sky-platform 저장소의 dev environment는 배포 브랜치를 main으로 제한해야 한다 (다른 브랜치가 이 역할을 받지 못하게).
    platform-deploy = {
      description = "sky-platform image push to ECR (dev environment)"
      subjects    = ["${local.platform_oidc_subject_prefix}:environment:${local.environment}"]
    }
    # sky-infra main에서 platform-image.auto.tfvars가 바뀌면 API·워커 태스크 정의와 서비스만 적용한다.
    # job에 environment를 걸면 sub가 environment:로 바뀌어 assume되지 않는다.
    platform-release = {
      description = "sky-infra main: apply platform image (task definitions and ECS services only)"
      subjects    = ["${local.infra_oidc_subject_prefix}:ref:refs/heads/main"]
    }
    }, var.github_builder_repository_id == "" ? {} : {
    # 저장소가 생성되고 불변 ID가 확인된 뒤에만 빌더 역할을 만든다.
    app-builder = {
      description = "sky-builder main: build deployed app images and push to ECR sky-managed"
      subjects    = ["${local.builder_oidc_subject_prefix}:ref:refs/heads/main"]
    }
  })

  # 키는 정적인 역할 이름. 값(정책 JSON)은 apply 전에 unknown이어도 된다.
  inline_policies = merge({
    platform-deploy  = module.iam.platform_deploy_policy_json
    platform-release = module.iam.platform_release_policy_json
    }, var.github_builder_repository_id == "" ? {} : {
    app-builder = module.iam.app_builder_policy_json
  })
}

# ---------------------------------------------------------------------------
# 컴퓨트: Fargate API(ALB 뒤, 최소 2) + 워커(큐 길이 기준 0~N)
# 같은 이미지를 쓰고 명령만 다르다. 이미지 태그는 platform-image.auto.tfvars 하나로 정한다.
# ---------------------------------------------------------------------------

module "cluster" {
  source              = "../../modules/ecs-cluster"
  cluster_name        = local.cluster_name
  exec_log_group_name = module.observability.exec_log_group_name
}

module "api" {
  source             = "../../modules/ecs-service"
  name               = local.service_names.api
  cluster_arn        = module.cluster.cluster_arn
  image              = local.image
  command            = var.api_command
  container_port     = local.app_port
  cpu                = var.api_cpu
  memory             = var.api_memory
  execution_role_arn = module.iam.execution_role_arns["api"]
  task_role_arn      = module.iam.api_task_role_arn
  subnet_ids         = module.network.app_subnet_ids
  security_group_id  = module.network.app_security_group_id
  target_group_arn   = module.edge.target_group_arn
  min_count          = var.api_min_count
  max_count          = var.api_max_count

  request_scaling = {
    resource_label      = "${module.edge.alb_arn_suffix}/${module.edge.target_group_arn_suffix}"
    requests_per_target = var.api_requests_per_target
  }
  cpu_target_percent = 60

  environment       = local.common_environment
  secrets           = local.service_secrets.api
  log_group_name    = module.observability.log_group_names["api"]
  log_stream_prefix = "api"
  depends_on_ids    = [module.edge.https_listener_arn, module.cluster.capacity_providers_ready]
}

module "worker" {
  source                = "../../modules/ecs-service"
  name                  = local.service_names.worker
  cluster_arn           = module.cluster.cluster_arn
  image                 = local.image
  command               = var.worker_command
  cpu                   = var.worker_cpu
  memory                = var.worker_memory
  ephemeral_storage_gib = 50  # 소스 스냅샷 압축·검사
  stop_timeout_seconds  = 120 # SIGTERM을 받으면 진행 중 단계를 기록하고 메시지를 놓아준다
  execution_role_arn    = module.iam.execution_role_arns["worker"]
  task_role_arn         = module.iam.worker_task_role_arn
  subnet_ids            = module.network.app_subnet_ids
  security_group_id     = module.network.worker_security_group_id
  min_count             = 0
  max_count             = var.worker_max_count

  queue_scaling = {
    queue_name   = module.queue.queue_name
    idle_minutes = var.worker_idle_minutes
  }

  environment = merge(local.common_environment, {
    SKY_AWS_ROLE_BOUNDARY_ARN  = module.iam.deployed_app_boundary_arn
    SKY_BUILDER_REPOSITORY     = "${local.org}/${var.builder_repository}"
    SKY_BUILDER_WORKFLOW       = var.builder_workflow
    SKY_BUILDER_REF            = var.builder_ref
    SKY_BUILDER_SHA            = var.builder_code_sha
    SKY_BUILDER_PLATFORM_SHA   = var.builder_platform_code_sha
    SKY_GITHUB_APP_ID          = var.github_builder_app_id
    SKY_GITHUB_INSTALLATION_ID = var.github_builder_installation_id
  })
  secrets           = local.service_secrets.worker
  log_group_name    = module.observability.log_group_names["worker"]
  log_stream_prefix = "worker"
  depends_on_ids    = [module.cluster.capacity_providers_ready]
}

# outbox publisher: DB outbox에 접수된 작업을 SQS FIFO로 보낸다. 항상 1개, 오토스케일링·ALB 없음.
# 태스크 역할은 API 것(DB 비밀 읽기, 큐 SendMessage)을 쓰고, 실행 역할은 비밀 없는 전용 역할을 쓴다.
module "outbox" {
  source             = "../../modules/ecs-service"
  name               = local.service_names.outbox
  cluster_arn        = module.cluster.cluster_arn
  image              = local.image
  command            = ["worker", "--mode", "outbox"]
  cpu                = 256
  memory             = 512
  execution_role_arn = module.iam.execution_role_arns["outbox"]
  task_role_arn      = module.iam.api_task_role_arn
  subnet_ids         = module.network.app_subnet_ids
  security_group_id  = module.network.worker_security_group_id # 들어오는 규칙 없음, RDS 5432 허용
  min_count          = 1
  max_count          = 1

  environment       = local.common_environment
  log_group_name    = module.observability.log_group_names["outbox"]
  log_stream_prefix = "outbox"
  depends_on_ids    = [module.cluster.capacity_providers_ready]
}

# ---------------------------------------------------------------------------
# 관측·공개 출력값
# ---------------------------------------------------------------------------

module "observability" {
  source                  = "../../modules/observability"
  name_prefix             = local.name_prefix
  alb_arn_suffix          = module.edge.alb_arn_suffix
  target_group_arn_suffix = module.edge.target_group_arn_suffix
  queue_name              = module.queue.queue_name
  dlq_name                = module.queue.dlq_name
  db_identifier           = module.state_db.identifier
}

module "published_outputs" {
  source           = "../../modules/published-outputs"
  environment      = local.environment
  contract_version = 2
  values = merge({
    "aws/region"     = var.region
    "aws/account_id" = data.aws_caller_identity.current.account_id

    # sky-platform CI가 서비스 서버 이미지를 push할 때 쓴다.
    "aws/platform_ecr_repository_url" = module.ecr.repository_url
    "aws/platform_deploy_role_arn"    = module.github_oidc.role_arns["platform-deploy"]

    # sky-builder 워크플로가 사용자 앱 이미지를 빌드할 때 쓴다.
    "aws/managed_ecr_repository_url" = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/sky-managed"
    "aws/artifacts_bucket"           = module.artifacts.bucket_name
    }, var.github_builder_repository_id == "" ? {} : {
    "aws/app_builder_role_arn" = module.github_oidc.role_arns["app-builder"]
  })
}
