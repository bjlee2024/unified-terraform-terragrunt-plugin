# Root Configuration for Terragrunt Live Environment
# Demonstrates: remote_state, provider generation, catalog configuration, DRY principles

# Local values that can be inherited by all child configurations
locals {
  # Parse the file path to extract environment and region
  # Expected path structure: live/<account>/<region>/<environment>/...
  path_parts  = split("/", path_relative_to_include())
  account_dir = length(local.path_parts) > 0 ? local.path_parts[0] : "default"
  region_dir  = length(local.path_parts) > 1 ? local.path_parts[1] : "us-east-1"
  env_dir     = length(local.path_parts) > 2 ? local.path_parts[2] : "dev"

  # AWS account ID mapping
  account_ids = {
    dev     = "123456789012"
    staging = "234567890123"
    prod    = "345678901234"
  }

  account_id = lookup(local.account_ids, local.env_dir, "123456789012")

  # Common tags applied to all resources
  common_tags = {
    ManagedBy   = "Terragrunt"
    Environment = local.env_dir
    Region      = local.region_dir
    Account     = local.account_dir
  }
}

# Remote state configuration - S3 backend with DynamoDB locking
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    # S3 bucket for state storage - one per account
    bucket = "terraform-state-${local.account_id}"

    # State file path includes environment and region for isolation
    key = "${local.env_dir}/${local.region_dir}/${path_relative_to_include()}/terraform.tfstate"

    # Primary region for state storage
    region = "us-east-1"

    # Enable encryption at rest
    encrypt = true

    # DynamoDB table for state locking
    dynamodb_table = "terraform-locks"

    # Enable versioning for state file history
    s3_bucket_tags = merge(
      local.common_tags,
      {
        Name    = "terraform-state-${local.account_id}"
        Purpose = "terraform-state"
      }
    )

    dynamodb_table_tags = merge(
      local.common_tags,
      {
        Name    = "terraform-locks"
        Purpose = "terraform-state-locking"
      }
    )

    # Skip validation for faster operations (optional)
    skip_bucket_versioning         = false
    skip_bucket_ssencryption       = false
    skip_bucket_root_access        = false
    skip_bucket_enforced_tls       = false
    skip_bucket_public_access_blocking = false

    # Enable bucket versioning and encryption
    enable_lock_table_ssencryption = true
  }
}

# Generate AWS provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# Auto-generated provider configuration

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "${local.region_dir}"

  # Assume role for cross-account access (optional)
  # assume_role {
  #   role_arn = "arn:aws:iam::${local.account_id}:role/TerraformExecutionRole"
  # }

  # Default tags applied to all resources
  default_tags {
    tags = {
      ManagedBy   = "Terragrunt"
      Environment = "${local.env_dir}"
      Region      = "${local.region_dir}"
      Terraform   = "true"
    }
  }
}

# Provider for us-east-1 (required for ACM certificates for CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  # assume_role {
  #   role_arn = "arn:aws:iam::${local.account_id}:role/TerraformExecutionRole"
  # }

  default_tags {
    tags = {
      ManagedBy   = "Terragrunt"
      Environment = "${local.env_dir}"
      Region      = "us-east-1"
      Terraform   = "true"
    }
  }
}
EOF
}

# Generate common variables file
generate "common_vars" {
  path      = "common_vars.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# Auto-generated common variables

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "${local.region_dir}"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "${local.env_dir}"
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
  default     = "${local.account_id}"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = ${jsonencode(local.common_tags)}
}
EOF
}

# Catalog configuration for units and stacks
catalog {
  # URLs to catalog repositories (can be git repos or local paths)
  urls = [
    "${get_repo_root()}/catalog",
    # "git::https://github.com/org/terraform-catalog.git//units?ref=v1.0.0",
  ]

  # Catalog refresh settings
  refresh_interval = 3600  # 1 hour
}

# Terragrunt configuration
terragrunt_version_constraint = ">= 0.67.0"

# Retry configuration for transient errors
retryable_errors = [
  "(?s).*Error.*acquiring the state lock.*",
  "(?s).*ssh_exchange_identification.*Connection closed by remote host.*",
  "(?s).*TLS handshake timeout.*",
  "(?s).*Error.*creating.*",
  "(?s).*Error.*updating.*",
  "(?s).*Error.*deleting.*",
]

retry_max_attempts       = 3
retry_sleep_interval_sec = 5

# Input defaults that can be overridden by child configurations
inputs = {
  # AWS configuration
  aws_region = local.region_dir
  environment = local.env_dir
  account_id  = local.account_id

  # Common tags
  common_tags = local.common_tags

  # Naming conventions
  name_prefix = "app"
  name_suffix = local.env_dir

  # Feature flags by environment
  enable_monitoring = local.env_dir == "prod" ? true : false
  enable_backups    = local.env_dir == "prod" ? true : false

  # High availability settings
  multi_az = local.env_dir == "prod" ? true : false

  # Cost optimization settings
  enable_spot_instances = local.env_dir != "prod" ? true : false

  # Compliance settings
  enable_encryption = true
  enable_logging    = true

  # Network configuration
  vpc_cidr = local.env_dir == "prod" ? "10.0.0.0/16" : "10.1.0.0/16"
}

# Hooks - actions to run before/after Terragrunt commands
terraform {
  # Before hook - validate Terraform files
  before_hook "before_hook" {
    commands     = ["apply", "plan"]
    execute      = ["echo", "Running Terraform ${local.env_dir} in ${local.region_dir}"]
    run_on_error = false
  }

  # After hook - notify on completion (example)
  after_hook "after_hook" {
    commands     = ["apply"]
    execute      = ["echo", "Terraform apply completed for ${local.env_dir}"]
    run_on_error = false
  }

  # Extra arguments to pass to all Terraform commands
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()

    optional_var_files = [
      "${get_terragrunt_dir()}/terraform.tfvars",
      "${get_terragrunt_dir()}/../terraform.tfvars",
      "${get_terragrunt_dir()}/../../terraform.tfvars",
    ]
  }

  # Disable init if provider cache is available
  extra_arguments "disable_input" {
    commands  = get_terraform_commands_that_need_input()
    arguments = ["-input=false"]
  }

  # Colorize output
  extra_arguments "colorize" {
    commands  = ["plan", "apply", "destroy"]
    arguments = ["-no-color"]  # Change to [] to enable color
  }
}

# Download directory for Terraform modules
download_dir = "${get_repo_root()}/.terragrunt-cache"

# Prevent destruction of critical resources
prevent_destroy = false  # Set to true for production

# IAM role configuration (if using cross-account access)
# iam_role = "arn:aws:iam::${local.account_id}:role/TerraformExecutionRole"

# Terraform source caching to speed up init
# terraform_binary = "terraform"  # or custom path to terraform binary

# Locals that can be accessed by child configurations
# These are exposed via read_terragrunt_config()
locals_for_child = {
  account_id  = local.account_id
  environment = local.env_dir
  region      = local.region_dir
  common_tags = local.common_tags
}
