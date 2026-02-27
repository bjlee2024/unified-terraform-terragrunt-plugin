# Terraform and Provider Version Constraints
# Demonstrates: proper version pinning, multiple providers

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration should be provided by the caller
  # Example for S3 backend:
  # backend "s3" {
  #   bucket         = "my-terraform-state"
  #   key            = "vpc/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

# Provider configuration with default tags
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Module    = "vpc"
    }
  }
}

# Additional provider variable (should be in variables.tf in real module)
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)"
  }
}
