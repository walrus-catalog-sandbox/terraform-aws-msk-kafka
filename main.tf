locals {
  project_name     = coalesce(try(var.context["project"]["name"], null), "default")
  project_id       = coalesce(try(var.context["project"]["id"], null), "default_id")
  environment_name = coalesce(try(var.context["environment"]["name"], null), "test")
  environment_id   = coalesce(try(var.context["environment"]["id"], null), "test_id")
  resource_name    = coalesce(try(var.context["resource"]["name"], null), "example")
  resource_id      = coalesce(try(var.context["resource"]["id"], null), "example_id")

  namespace = join("-", [local.project_name, local.environment_name])

  tags = {
    "Name" = join("-", [local.namespace, local.resource_name])

    "walrus.seal.io/catalog-name"     = "terraform-aws-msk-kafka"
    "walrus.seal.io/project-id"       = local.project_id
    "walrus.seal.io/environment-id"   = local.environment_id
    "walrus.seal.io/resource-id"      = local.resource_id
    "walrus.seal.io/project-name"     = local.project_name
    "walrus.seal.io/environment-name" = local.environment_name
    "walrus.seal.io/resource-name"    = local.resource_name
  }
}

#
# Ensure
#

data "aws_vpc" "selected" {
  id = var.infrastructure.vpc_id

  state = "available"
}

data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) > 0
      error_message = "VPC needs to have at least one subnet"
    }
  }
}

data "aws_kms_key" "selected" {
  count = var.infrastructure.kms_key_id != null ? 1 : 0

  key_id = var.infrastructure.kms_key_id

  lifecycle {
    postcondition {
      condition     = self.enabled
      error_message = "KMS key needs to be enabled"
    }
  }
}

#
# Random
#

# create a random password for blank password input.

resource "random_password" "password" {
  length      = 16
  special     = false
  lower       = true
  min_lower   = 3
  min_upper   = 3
  min_numeric = 3
}

# create the name with a random suffix.

resource "random_string" "name_suffix" {
  length  = 10
  special = false
  upper   = false
}

locals {
  name        = join("-", [local.resource_name, random_string.name_suffix.result])
  fullname    = join("-", [local.namespace, local.name])
  description = "Created by Walrus catalog, and provisioned by Terraform."
  version     = coalesce(var.engine_version, "3.6.0")
}

#
# Deployment
#

# create subnet group.

resource "aws_db_subnet_group" "target" {
  name        = local.fullname
  description = local.description
  tags        = local.tags

  subnet_ids = data.aws_subnets.selected.ids
}

# create security group.

resource "aws_security_group" "target" {
  name        = local.fullname
  description = local.description
  tags        = local.tags

  vpc_id = data.aws_vpc.selected.id
}

resource "aws_security_group_rule" "target" {
  description = local.description

  security_group_id = aws_security_group.target.id
  type              = "ingress"
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  from_port         = 9094
  to_port           = 9094
}

resource "aws_msk_configuration" "config" {
  kafka_versions = [local.version]
  name           = local.fullname
  description    = "Configuration for Amazon Managed Streaming for Kafka"

  server_properties = join("\n", [for k, v in var.engine_parameters : format("%s = %s", k, v)])

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_msk_cluster" "default" {
  cluster_name           = local.fullname
  kafka_version          = local.version
  tags                   = local.tags
  number_of_broker_nodes = var.broker_per_zone * length(data.aws_subnets.selected.ids)

  broker_node_group_info {
    instance_type   = try(var.resources.class, "kafka.t3.small")
    client_subnets  = data.aws_subnets.selected.ids
    security_groups = [aws_security_group.target.id]

    storage_info {
      ebs_storage_info {
        volume_size = try(var.storage.size / 1024, 20)
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.config.arn
    revision = aws_msk_configuration.config.latest_revision
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = data.aws_kms_key.selected[0].arn

    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = try(data.aws_kms_key.selected[0].arn != null, false)
    }
  }
  client_authentication {
    # Unauthenticated cannot be set to `false` without enabling any authentication mechanisms
    unauthenticated = !try(var.sasl_authentication.scram, false) && !try(var.sasl_authentication.iam, false)

    sasl {
      scram = try(var.sasl_authentication.scram, false)
      iam   = try(var.sasl_authentication.iam, false)
    }
  }

  lifecycle {
    ignore_changes = [
      broker_node_group_info[0].storage_info[0].ebs_storage_info[0].volume_size,
    ]
  }
}
