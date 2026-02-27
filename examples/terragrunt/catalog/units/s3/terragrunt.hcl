# S3 Bucket Unit
# Demonstrates: values pattern, dependencies with mock outputs, computed values

terraform {
  source = "tfr:///terraform-aws-modules/s3-bucket/aws?version=4.2.2"
}

# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Dependencies on other units
dependency "kms" {
  config_path = "../kms"

  # Mock outputs for planning without dependencies
  mock_outputs = {
    key_id  = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "cloudtrail_role" {
  config_path = "../iam/cloudtrail-role"

  mock_outputs = {
    role_arn = "arn:aws:iam::123456789012:role/cloudtrail-role"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

# Local values for this unit
locals {
  # Load environment values
  env_values = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_values.locals.environment

  # Load common values
  common_values = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  project       = local.common_values.locals.project
  region        = local.common_values.locals.region

  # Unit-specific values (can be overridden in stack)
  default_values = {
    bucket_prefix = "${local.project}-${local.environment}"
    versioning_enabled = true
    lifecycle_rules = [
      {
        id      = "archive-old-versions"
        enabled = true
        transitions = [
          {
            days          = 30
            storage_class = "STANDARD_IA"
          },
          {
            days          = 90
            storage_class = "GLACIER"
          }
        ]
        noncurrent_version_expiration = {
          days = 365
        }
      }
    ]
  }

  # Merge with values passed from stack
  values = merge(local.default_values, try(local.stack_values, {}))
}

# Accept values from stack
locals {
  stack_values = try(var.values, {})
}

variable "values" {
  description = "Values passed from stack or parent configuration"
  type        = any
  default     = {}
}

# Inputs to the module
inputs = {
  # Bucket name - use prefix from values or generate
  bucket = try(
    local.values.bucket_name,
    "${local.values.bucket_prefix}-${local.region}"
  )

  # Access control
  acl = try(local.values.acl, "private")

  # Versioning
  versioning = {
    enabled = local.values.versioning_enabled
  }

  # Server-side encryption with KMS from dependency
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = dependency.kms.outputs.key_id
      }
      bucket_key_enabled = true
    }
  }

  # Lifecycle rules from values
  lifecycle_rule = local.values.lifecycle_rules

  # Block public access
  block_public_acls       = try(local.values.block_public_access, true)
  block_public_policy     = try(local.values.block_public_access, true)
  ignore_public_acls      = try(local.values.block_public_access, true)
  restrict_public_buckets = try(local.values.block_public_access, true)

  # Logging
  logging = try(local.values.logging_enabled, false) ? {
    target_bucket = try(local.values.logging_bucket, "")
    target_prefix = try(local.values.logging_prefix, "logs/")
  } : {}

  # Object lock (for compliance)
  object_lock_enabled = try(local.values.object_lock_enabled, false)

  object_lock_configuration = try(local.values.object_lock_enabled, false) ? {
    rule = {
      default_retention = {
        mode = try(local.values.object_lock_mode, "GOVERNANCE")
        days = try(local.values.object_lock_days, 30)
      }
    }
  } : null

  # Replication (if configured)
  replication_configuration = try(local.values.replication, null) != null ? {
    role = dependency.cloudtrail_role.outputs.role_arn

    rules = [
      {
        id       = "replicate-all"
        status   = "Enabled"
        priority = 10

        filter = {
          prefix = ""
        }

        destination = {
          bucket        = local.values.replication.destination_bucket
          storage_class = try(local.values.replication.storage_class, "STANDARD")

          replication_time = {
            status  = "Enabled"
            minutes = 15
          }

          metrics = {
            status  = "Enabled"
            minutes = 15
          }
        }
      }
    ]
  } : null

  # CORS rules (for web access)
  cors_rule = try(local.values.cors_rules, [])

  # Website configuration (for static hosting)
  website = try(local.values.website, null)

  # Intelligent tiering
  intelligent_tiering = try(local.values.intelligent_tiering, {})

  # Tags
  tags = merge(
    {
      Environment = local.environment
      Project     = local.project
      ManagedBy   = "Terragrunt"
      Unit        = "s3"
    },
    try(local.values.tags, {})
  )
}

# Outputs to expose to other units
outputs = {
  bucket_id = {
    description = "The name of the bucket"
    value       = dependency.outputs.s3_bucket_id
  }

  bucket_arn = {
    description = "The ARN of the bucket"
    value       = dependency.outputs.s3_bucket_arn
  }

  bucket_domain_name = {
    description = "The bucket domain name"
    value       = dependency.outputs.s3_bucket_bucket_domain_name
  }

  bucket_regional_domain_name = {
    description = "The bucket region-specific domain name"
    value       = dependency.outputs.s3_bucket_bucket_regional_domain_name
  }

  website_endpoint = {
    description = "The website endpoint, if configured"
    value       = try(dependency.outputs.s3_bucket_website_endpoint, null)
  }
}
