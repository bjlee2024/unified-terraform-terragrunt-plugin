# VPC Module Variables
# Demonstrates: proper descriptions, types, defaults, validation

variable "name" {
  description = "Name prefix for all VPC resources"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 32
    error_message = "Name must be between 1 and 32 characters"
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block"
  }
}

variable "subnets" {
  description = <<-EOT
    Map of subnets to create. Each subnet requires:
    - cidr: CIDR block for the subnet
    - az: Availability zone
    - public: Whether subnet is public (has IGW route)
    - tags: (optional) Additional tags for the subnet
  EOT
  type = map(object({
    cidr   = string
    az     = string
    public = bool
    tags   = optional(map(string), {})
  }))

  validation {
    condition     = length(var.subnets) > 0
    error_message = "At least one subnet must be defined"
  }

  validation {
    condition = alltrue([
      for k, v in var.subnets : can(cidrhost(v.cidr, 0))
    ])
    error_message = "All subnet CIDRs must be valid IPv4 CIDR blocks"
  }
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway(s) for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets (cost optimization)"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = false
}

variable "flow_logs_role_arn" {
  description = "IAM role ARN for VPC Flow Logs (required if enable_flow_logs is true)"
  type        = string
  default     = null

  validation {
    condition = (
      !var.enable_flow_logs ||
      (var.enable_flow_logs && var.flow_logs_role_arn != null)
    )
    error_message = "flow_logs_role_arn is required when enable_flow_logs is true"
  }
}

variable "flow_logs_destination" {
  description = "Destination for VPC Flow Logs (CloudWatch Log Group ARN or S3 bucket ARN)"
  type        = string
  default     = null

  validation {
    condition = (
      !var.enable_flow_logs ||
      (var.enable_flow_logs && var.flow_logs_destination != null)
    )
    error_message = "flow_logs_destination is required when enable_flow_logs is true"
  }
}

variable "enable_s3_endpoint" {
  description = "Create VPC endpoint for S3"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.tags : can(regex("^[a-zA-Z0-9_-]+$", k))
    ])
    error_message = "Tag keys must contain only alphanumeric characters, hyphens, and underscores"
  }
}
