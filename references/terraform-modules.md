# Terraform Modules Reference

Complete guide to Terraform module development, hierarchy, and best practices.

---

## Table of Contents

1. [Module Hierarchy](#module-hierarchy)
2. [Module Interface Design](#module-interface-design)
3. [Standard Module Structure](#standard-module-structure)
4. [Version Constraints](#version-constraints)
5. [Module Sources](#module-sources)
6. [State Migration with Moved Blocks](#state-migration-with-moved-blocks)
7. [Refactoring Patterns](#refactoring-patterns)
8. [Module Testing Strategy](#module-testing-strategy)
9. [Provider Passthrough Pattern](#provider-passthrough-pattern)
10. [Anti-Patterns](#anti-patterns)

---

## Module Hierarchy

Terraform modules should follow a clear hierarchy from atomic resources to full infrastructure stacks.

### The Module Pyramid

```
Infrastructure Stack (Environment Level)
└── Root Module
    ├── Environment-specific config (dev/staging/prod)
    └── Composition Modules
        ├── Service boundaries (networking, compute, data)
        └── Resource Modules
            ├── Single resource type (VPC, EC2, RDS)
            └── Atomic Resources
                └── Individual resources (subnets, security groups)
```

### Hierarchy Levels Explained

| Level | Purpose | Example | Scope |
|-------|---------|---------|-------|
| **Root Module** | Environment config | `environments/prod/` | Complete environment |
| **Composition Module** | Service boundaries | `services/web-app/` | Logical service grouping |
| **Resource Module** | Single resource type | `modules/vpc/` | One AWS service |
| **Atomic Resource** | Individual resource | `aws_subnet.private` | Single resource |

### Example Structure

```
infrastructure/
├── modules/                    # Reusable resource modules
│   ├── vpc/                   # Resource module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/               # Resource module
│   └── database/              # Resource module
├── compositions/              # Composition modules
│   ├── web-service/          # Combines compute + lb + dns
│   └── data-pipeline/        # Combines database + queues + lambda
└── environments/             # Root modules
    ├── dev/
    ├── staging/
    └── prod/
```

### Design Principles

1. **Bottom-Up Composition**: Build from atomic resources up
2. **Single Responsibility**: Each level has one clear purpose
3. **Reusability**: Lower levels more reusable than higher levels
4. **Encapsulation**: Hide complexity at each level

---

## Module Interface Design

A well-designed module interface is the key to reusable, maintainable infrastructure code.

### Variable Design Principles

#### Required vs Optional Variables

```hcl
# variables.tf

# Required: No default, must be provided
variable "project_name" {
  description = "Name of the project (used in resource naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# Optional: Has sensible default
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}
```

#### Complex Types with Defaults

```hcl
variable "vpc_config" {
  description = "VPC configuration"
  type = object({
    cidr_block           = string
    enable_dns_hostnames = bool
    enable_dns_support   = bool
    availability_zones   = list(string)
  })
  default = {
    cidr_block           = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support   = true
    availability_zones   = ["us-east-1a", "us-east-1b"]
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

#### Validation Rules

```hcl
variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "instance_count" {
  description = "Number of instances to create"
  type        = number

  validation {
    condition     = var.instance_count > 0 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}
```

### Output Design Principles

#### Output Everything Needed by Consumers

```hcl
# outputs.tf

# IDs for referencing resources
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

# ARNs for IAM policies
output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.main.arn
}

# Connection strings
output "database_endpoint" {
  description = "The connection endpoint for the database"
  value       = aws_db_instance.main.endpoint
}

# Lists for iteration
output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

# Maps for lookup
output "subnet_by_az" {
  description = "Map of availability zone to subnet ID"
  value = {
    for subnet in aws_subnet.private :
    subnet.availability_zone => subnet.id
  }
}
```

#### Sensitive Outputs

```hcl
output "database_password" {
  description = "The master password for the database"
  value       = aws_db_instance.main.password
  sensitive   = true  # Prevents display in logs
}
```

#### Output Documentation

```hcl
output "load_balancer_dns" {
  description = <<-EOT
    DNS name of the load balancer.
    Use this to configure your DNS CNAME record.
    Example: app.example.com -> ${this_value}
  EOT
  value = aws_lb.main.dns_name
}
```

---

## Standard Module Structure

Consistent module structure improves maintainability and team collaboration.

### Core Files (Always Present)

```
my-module/
├── main.tf           # Primary resource definitions
├── variables.tf      # Input variable declarations
├── outputs.tf        # Output value declarations
├── versions.tf       # Provider version requirements
└── README.md         # Module documentation
```

### Optional Files

```
my-module/
├── locals.tf         # Local value computations
├── data.tf           # Data source queries
├── providers.tf      # Provider configuration (if needed)
└── examples/         # Usage examples
    ├── basic/
    └── complete/
```

### File Content Guidelines

#### main.tf

```hcl
# Primary resources for this module
# Group related resources together

# VPC Resources
resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-vpc"
    }
  )
}

# Subnet Resources
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-private-${count.index + 1}"
      Type = "private"
    }
  )
}
```

#### variables.tf

```hcl
# Group related variables together
# Order: required first, then optional

# Required Variables
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Network Configuration
variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# Feature Flags
variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

#### outputs.tf

```hcl
# Group related outputs together
# Include comprehensive descriptions

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}
```

#### versions.tf (NOT terraform.tf)

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

#### locals.tf

```hcl
# Local value computations
# Use for DRY principle and complex expressions

locals {
  # Common tags applied to all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # Computed values
  vpc_name = "${var.project_name}-${var.environment}-vpc"

  # Complex transformations
  subnet_map = {
    for idx, az in var.availability_zones :
    az => {
      cidr_block = cidrsubnet(var.cidr_block, 8, idx)
      subnet_id  = aws_subnet.private[idx].id
    }
  }
}
```

---

## Version Constraints

Proper version constraints ensure stability and controlled updates.

### Version Constraint Operators

| Operator | Meaning | Example | Allows |
|----------|---------|---------|--------|
| `=` | Exact version | `= 1.2.3` | Only 1.2.3 |
| `!=` | Not equal | `!= 1.2.3` | Any except 1.2.3 |
| `>` | Greater than | `> 1.2.3` | 1.2.4, 1.3.0, 2.0.0 |
| `>=` | Greater or equal | `>= 1.2.3` | 1.2.3, 1.2.4, 2.0.0 |
| `<` | Less than | `< 1.2.3` | 1.2.2, 1.1.0, 1.0.0 |
| `<=` | Less or equal | `<= 1.2.3` | 1.2.3, 1.2.2, 1.0.0 |
| `~>` | Pessimistic | `~> 1.2` | 1.2.x only |

### Version Constraint Strategies

#### Development: Flexible Updates

```hcl
# Allow all patch versions (1.2.x)
version = "~> 1.2"

# Allow minor and patch updates (1.x.x)
version = "~> 1.0"
```

#### Production: Stability First

```hcl
# Exact version for maximum stability
version = "1.2.3"

# Allow only patch updates
version = "~> 1.2.3"  # Allows 1.2.4, 1.2.5, but not 1.3.0
```

#### Version Range

```hcl
# Minimum with maximum
version = ">= 3.0, < 4.0"

# Multiple constraints
version = ">= 1.2.0, != 1.2.5, < 2.0.0"
```

### Provider Version Constraints

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Allow minor updates
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0, < 3.0.0"
    }
  }
}
```

---

## Module Sources

Terraform supports multiple module source types.

### Terraform Registry (Recommended)

```hcl
# Public registry
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"
}

# Private registry
module "internal" {
  source  = "app.terraform.io/my-org/vpc/aws"
  version = "1.2.3"
}
```

### GitHub

```hcl
# GitHub HTTPS
module "vpc" {
  source = "github.com/hashicorp/example?ref=v1.2.0"
}

# GitHub SSH
module "vpc" {
  source = "git@github.com:hashicorp/example.git?ref=v1.2.0"
}

# Subdirectory
module "vpc" {
  source = "github.com/hashicorp/example//modules/vpc?ref=v1.2.0"
}

# Branch or commit
module "vpc" {
  source = "github.com/hashicorp/example?ref=main"
}
```

### Git (Generic)

```hcl
# HTTPS
module "vpc" {
  source = "git::https://example.com/vpc.git?ref=v1.0.0"
}

# SSH
module "vpc" {
  source = "git::ssh://git@example.com/vpc.git?ref=v1.0.0"
}
```

### Local Path

```hcl
# Relative path
module "vpc" {
  source = "../modules/vpc"
}

# Absolute path
module "vpc" {
  source = "/home/user/terraform/modules/vpc"
}
```

### S3 Bucket

```hcl
module "vpc" {
  source = "s3::https://s3-eu-west-1.amazonaws.com/bucket/module.zip"
}

# With specific region
module "vpc" {
  source = "s3::https://s3.amazonaws.com/bucket/module.zip?region=us-west-2"
}
```

### HTTP/HTTPS

```hcl
module "vpc" {
  source = "https://example.com/vpc-module.zip"
}
```

---

## State Migration with Moved Blocks

The `moved` block enables safe resource refactoring without destroying resources.

### Basic Resource Rename

```hcl
# Rename a resource
moved {
  from = aws_instance.old_name
  to   = aws_instance.new_name
}
```

### Move Resource Into Module

```hcl
# Before: Resource in root
resource "aws_instance" "web" {
  ami           = "ami-12345678"
  instance_type = "t3.micro"
}

# After: Resource in module
module "compute" {
  source = "./modules/compute"
}

# Migration
moved {
  from = aws_instance.web
  to   = module.compute.aws_instance.web
}
```

### Move Resource Between Modules

```hcl
moved {
  from = module.old_module.aws_instance.this
  to   = module.new_module.aws_instance.this
}
```

### Move Resource with Count

```hcl
# Moving from single to count
moved {
  from = aws_instance.web
  to   = aws_instance.web[0]
}

# Moving specific count index
moved {
  from = aws_instance.web[0]
  to   = aws_instance.web[2]
}
```

### Move Resource with For_each

```hcl
moved {
  from = aws_instance.web["old-key"]
  to   = aws_instance.web["new-key"]
}
```

### Multiple Moves

```hcl
# Refactor multiple resources at once
moved {
  from = aws_instance.web
  to   = module.compute.aws_instance.web
}

moved {
  from = aws_security_group.web
  to   = module.compute.aws_security_group.web
}

moved {
  from = aws_eip.web
  to   = module.compute.aws_eip.web
}
```

---

## Refactoring Patterns

Common module refactoring scenarios.

### Extract Module from Root

**Before:**

```hcl
# main.tf
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count      = 2
  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
}
```

**After:**

```hcl
# main.tf
module "vpc" {
  source     = "./modules/vpc"
  cidr_block = "10.0.0.0/16"
}

# migrations.tf
moved {
  from = aws_vpc.main
  to   = module.vpc.aws_vpc.main
}

moved {
  from = aws_subnet.public
  to   = module.vpc.aws_subnet.public
}
```

### Split Large Module

**Before: Single monolithic module**

```hcl
module "infrastructure" {
  source = "./modules/infrastructure"
  # 50+ variables
}
```

**After: Split into focused modules**

```hcl
module "networking" {
  source = "./modules/networking"
}

module "compute" {
  source     = "./modules/compute"
  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
}

module "database" {
  source     = "./modules/database"
  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
}

# migrations.tf
moved {
  from = module.infrastructure.aws_vpc.main
  to   = module.networking.aws_vpc.main
}

moved {
  from = module.infrastructure.aws_instance.app
  to   = module.compute.aws_instance.app
}

moved {
  from = module.infrastructure.aws_db_instance.main
  to   = module.database.aws_db_instance.main
}
```

### Merge Related Modules

```hcl
# Before: Separate modules
module "alb" {
  source = "./modules/alb"
}

module "target_group" {
  source = "./modules/target-group"
}

# After: Combined module
module "load_balancer" {
  source = "./modules/load-balancer"
}

# migrations.tf
moved {
  from = module.alb.aws_lb.main
  to   = module.load_balancer.aws_lb.main
}

moved {
  from = module.target_group.aws_lb_target_group.main
  to   = module.load_balancer.aws_lb_target_group.main
}
```

---

## Module Testing Strategy

Comprehensive testing ensures module reliability.

### Testing Pyramid

```
         Unit Tests (Mock Providers)
        /     Fast, isolated tests
       /
      /       Integration Tests (Real Providers)
     /        Full resource creation
    /
   /          Contract Tests (Module Interface)
  /           Input/output validation
```

### Unit Testing with Terraform Test

```hcl
# tests/unit/vpc_test.tftest.hcl
run "validate_vpc_cidr" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/16"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block mismatch"
  }
}

run "validate_tags" {
  command = plan

  variables {
    project_name = "test"
    environment  = "dev"
    tags = {
      Owner = "TeamA"
    }
  }

  assert {
    condition     = aws_vpc.main.tags["Project"] == "test"
    error_message = "Project tag not set correctly"
  }
}
```

### Integration Testing

```hcl
# tests/integration/full_test.tftest.hcl
run "create_infrastructure" {
  command = apply

  variables {
    project_name = "integration-test"
    environment  = "test"
  }

  assert {
    condition     = output.vpc_id != ""
    error_message = "VPC was not created"
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "Expected 2 private subnets"
  }
}
```

### Contract Testing

```hcl
# tests/contract/interface_test.tftest.hcl
run "required_outputs_present" {
  command = plan

  assert {
    condition     = can(output.vpc_id)
    error_message = "Module must output vpc_id"
  }

  assert {
    condition     = can(output.private_subnet_ids)
    error_message = "Module must output private_subnet_ids"
  }
}
```

---

## Provider Passthrough Pattern

Modules should not configure providers; they should receive them from the caller.

### Module Provider Requirements

```hcl
# modules/vpc/versions.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
      # No configuration block
    }
  }
}
```

### Calling Module with Provider

```hcl
# environments/prod/main.tf
provider "aws" {
  alias  = "us_east"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_west"
  region = "us-west-2"
}

module "vpc_east" {
  source = "../../modules/vpc"

  providers = {
    aws = aws.us_east
  }

  cidr_block = "10.0.0.0/16"
}

module "vpc_west" {
  source = "../../modules/vpc"

  providers = {
    aws = aws.us_west
  }

  cidr_block = "10.1.0.0/16"
}
```

---

## Anti-Patterns

Common mistakes to avoid in module development.

### 1. Hardcoded Values

```hcl
# BAD: Hardcoded
resource "aws_instance" "web" {
  ami           = "ami-12345678"  # NEVER hardcode AMIs
  instance_type = "t3.micro"
}

# GOOD: Parameterized
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type
}
```

### 2. Too Many Required Variables

```hcl
# BAD: 20 required variables
variable "var1" { type = string }
variable "var2" { type = string }
# ... 18 more

# GOOD: Group related config
variable "vpc_config" {
  type = object({
    cidr_block = string
    azs        = list(string)
    # ... grouped settings
  })
  default = {
    cidr_block = "10.0.0.0/16"
    azs        = ["us-east-1a", "us-east-1b"]
  }
}
```

### 3. Missing Outputs

```hcl
# BAD: No outputs
# Consumers cannot reference resources

# GOOD: Output everything needed
output "vpc_id" {
  value = aws_vpc.main.id
}
output "subnet_ids" {
  value = aws_subnet.private[*].id
}
```

### 4. Circular Dependencies

```hcl
# BAD: Module A depends on B, B depends on A
module "app" {
  security_group_id = module.database.security_group_id
}

module "database" {
  security_group_id = module.app.security_group_id
}

# GOOD: Create shared security group module
module "security" { }
module "app" {
  security_group_id = module.security.app_sg_id
}
module "database" {
  security_group_id = module.security.db_sg_id
}
```

### 5. Provider Configuration in Modules

```hcl
# BAD: Provider in module
provider "aws" {
  region = "us-east-1"  # NEVER configure providers in modules
}

# GOOD: Use provider passthrough
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}
```

---

## Summary

Key principles for effective Terraform modules:

1. **Hierarchy**: Build from atomic resources up through composition modules to root modules
2. **Interface**: Design clear, well-documented variable and output interfaces
3. **Structure**: Follow standard file organization for consistency
4. **Versioning**: Use appropriate version constraints for stability and updates
5. **Sources**: Choose the right module source for your workflow
6. **Migration**: Use `moved` blocks for safe refactoring
7. **Testing**: Implement comprehensive testing at multiple levels
8. **Providers**: Use provider passthrough pattern, never configure in modules
9. **Avoid Anti-Patterns**: Don't hardcode, over-require, or create circular dependencies

Well-designed modules are the foundation of scalable, maintainable infrastructure as code.
