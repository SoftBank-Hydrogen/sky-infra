# [Network] VPC 3계층(퍼블릭·앱·데이터), NAT, 보안 그룹

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  azs = keys(var.public_subnet_cidrs)
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true # RDS 엔드포인트 이름 해석에 필요

  tags = { Name = var.name_prefix }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name_prefix }
}

resource "aws_subnet" "public" {
  for_each          = var.public_subnet_cidrs
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name_prefix}-public-${each.key}", "sky:tier" = "public" }
}

resource "aws_subnet" "app" {
  for_each          = var.app_subnet_cidrs
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name_prefix}-app-${each.key}", "sky:tier" = "app" }
}

resource "aws_subnet" "data" {
  for_each          = var.data_subnet_cidrs
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "${var.name_prefix}-data-${each.key}", "sky:tier" = "data" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = aws_subnet.public
  domain   = "vpc"
  tags     = { Name = "${var.name_prefix}-nat-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = aws_subnet.public
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  tags          = { Name = "${var.name_prefix}-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "app" {
  for_each = aws_subnet.app
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name_prefix}-app-${each.key}" }
}

resource "aws_route" "app_nat" {
  for_each               = aws_route_table.app
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# 데이터 라우팅: 인터넷 경로가 없다. VPC 내부와 S3 엔드포인트만 쓴다
resource "aws_route_table" "data" {
  for_each = aws_subnet.data
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name_prefix}-data-${each.key}" }
}

resource "aws_route_table_association" "data" {
  for_each       = aws_subnet.data
  subnet_id      = each.value.id
  route_table_id = aws_route_table.data[each.key].id
}

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [for rt in aws_route_table.app : rt.id],
    [for rt in aws_route_table.data : rt.id],
  )
  tags = { Name = "${var.name_prefix}-s3" }
}

# 보안 그룹
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Sky ALB"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.alb.id
  description       = "HTTP(S) from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To Sky app"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# Cognito 인증 액션은 ALB가 Cognito 토큰 엔드포인트를 HTTPS로 호출해야 함
resource "aws_vpc_security_group_egress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS to Cognito IdP"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# API 태스크. ALB에서만 들어온다.
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app"
  description = "Sky API tasks"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "From ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound to AWS, GCP, OpenAI, GitHub"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# 워커 태스크. 들어오는 연결은 없고 나가기만 한다.
resource "aws_security_group" "worker" {
  name        = "${var.name_prefix}-worker"
  description = "Sky worker tasks (egress only)"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-worker" }
}

resource "aws_vpc_security_group_egress_rule" "worker_all" {
  security_group_id = aws_security_group.worker.id
  description       = "Outbound to AWS, GCP, OpenAI, GitHub"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# 상태 DB. API와 워커에서만 들어온다.
resource "aws_security_group" "data" {
  name        = "${var.name_prefix}-data"
  description = "Sky state database"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-data" }
}

resource "aws_vpc_security_group_ingress_rule" "data_from_tasks" {
  for_each = {
    app    = aws_security_group.app.id
    worker = aws_security_group.worker.id
  }
  security_group_id            = aws_security_group.data.id
  description                  = "PostgreSQL from ${each.key} tasks"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
