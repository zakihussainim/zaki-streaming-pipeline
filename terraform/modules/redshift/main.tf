terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  redshift_subnet_ids = [
    for s in data.aws_subnet.default : s.id
    if s.availability_zone != "eu-west-2d"
  ]
}

resource "aws_redshiftserverless_namespace" "this" {
  namespace_name         = "${var.project_prefix}-namespace"
  db_name                = var.database_name
  manage_admin_password  = true
}

resource "aws_redshiftserverless_workgroup" "this" {
  namespace_name       = aws_redshiftserverless_namespace.this.namespace_name
  workgroup_name        = "${var.project_prefix}-workgroup"
  base_capacity          = 8
  subnet_ids             = local.redshift_subnet_ids
  publicly_accessible    = false
}