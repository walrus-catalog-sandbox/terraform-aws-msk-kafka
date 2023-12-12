#
# Contextual Fields
#

variable "context" {
  description = <<-EOF
Receive contextual information. When Walrus deploys, Walrus will inject specific contextual information into this field.

Examples:
```
context:
  project:
    name: string
    id: string
  environment:
    name: string
    id: string
  resource:
    name: string
    id: string
```
EOF
  type        = map(any)
  default     = {}
}

#
# Infrastructure Fields
#

variable "infrastructure" {
  description = <<-EOF
Specify the infrastructure information for deploying.

Examples:
```
infrastructure:
  vpc_id: string                  # the ID of the VPC where the Kafka service applies
  kms_key_id: string,optional     # the ID of the KMS key which to encrypt the Kafka data
```
EOF
  type = object({
    vpc_id     = string
    kms_key_id = optional(string)
  })
}

#
# Deployment Fields
#

variable "broker_per_zone" {
  description = <<-EOF
The desired number of broker nodes per zone in the kafka cluster.
EOF
  type        = number
  default     = 1
  validation {
    condition     = var.broker_per_zone > 0
    error_message = "The broker_per_zone value must be at least 1."
  }
  nullable = false
}

variable "engine_version" {
  description = <<-EOF
Specify the deployment engine version, select from https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html.
EOF
  type        = string
  default     = "3.6.0"
}

variable "engine_parameters" {
  description = <<-EOF
Specify the deployment engine parameters, select for https://docs.aws.amazon.com/msk/latest/developerguide/msk-configuration-properties.html.
EOF
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "sasl_authentication" {
  description = <<-EOF
Specify the SASL authentication information for the Kafka service.
EOF
  type = object({
    scram = optional(bool, false)
    iam   = optional(bool, false)
  })
  default = {
    scram = false
    iam   = false
  }
}

variable "resources" {
  description = <<-EOF
Specify the computing resources.

Examples:
```
resources:
  class: string, optional         # https://aws.amazon.com/msk/pricing/
```
EOF
  type = object({
    class = optional(string, "kafka.t3.small")
  })
  default = {
    class = "kafka.t3.small"
  }
}

variable "storage" {
  description = <<-EOF
Specify the storage resources.

Examples:
```
storage:
  size: number, optional         # in megabyte
```
EOF
  type = object({
    size = optional(number, 20 * 1024)
  })
  default = {
    size = 20 * 1024
  }
}
