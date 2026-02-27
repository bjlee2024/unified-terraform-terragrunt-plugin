# Terraform/OpenTofu Patterns Reference

Comprehensive guide to Terraform and OpenTofu coding patterns, conventions, and modern features.

---

## Table of Contents

1. [Block Ordering Convention](#block-ordering-convention)
2. [Count vs For_Each Decision Matrix](#count-vs-for_each-decision-matrix)
3. [Modern Terraform Features](#modern-terraform-features)
4. [Variable Validation Patterns](#variable-validation-patterns)
5. [Dynamic Blocks](#dynamic-blocks)
6. [Naming Conventions](#naming-conventions)
7. [Common Anti-Patterns](#common-anti-patterns)

---

## Block Ordering Convention

Maintain consistent block ordering for readability and maintainability:

```hcl
# 1. terraform block (versions, backend, required_providers)
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "my-terraform-state"
    key    = "prod/vpc/terraform.tfstate"
    region = "us-west-2"
  }
}

# 2. provider blocks
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# 3. data sources
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# 4. local values
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  az_count = min(length(data.aws_availability_zones.available.names), 3)
}

# 5. resources (grouped by logical relationship)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_subnet" "private" {
  for_each = toset(slice(data.aws_availability_zones.available.names, 0, local.az_count))

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(data.aws_availability_zones.available.names, each.value))
  availability_zone = each.value

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${each.value}"
    Type = "private"
  })
}

# 6. outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = values(aws_subnet.private)[*].id
}
```

---

## Count vs For_Each Decision Matrix

| Situation | Use | Reason | Example |
|-----------|-----|--------|---------|
| Resources from list/set | `for_each` | Stable addressing, resilient to reordering | Creating subnets from AZ list |
| Conditional resource | `count` | Simple toggle (0 or 1) | `count = var.enabled ? 1 : 0` |
| Identical copies | `count` | Index-based OK, simpler | Creating N identical resources |
| Map-based resources | `for_each` | Key-based addressing, semantic keys | Creating IAM users from map |
| Complex conditional logic | `for_each` with `for` | Filtering, transforming | `for_each = { for x in var.items : x.name => x if x.enabled }` |

### Examples

#### ✅ Conditional Resource with Count
```hcl
resource "aws_db_instance" "replica" {
  count = var.enable_read_replica ? 1 : 0

  replicate_source_db = aws_db_instance.primary.id
  instance_class      = var.replica_instance_class
}

# Access: aws_db_instance.replica[0] (if created)
```

#### ✅ Resources from List with For_Each
```hcl
variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

resource "aws_subnet" "public" {
  for_each = toset(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(var.availability_zones, each.value))

  tags = {
    Name = "public-${each.value}"
  }
}

# Access: aws_subnet.public["us-west-2a"]
# Resilient: Removing us-west-2b doesn't affect us-west-2c
```

#### ❌ Antipattern: Count with List (fragile)
```hcl
# BAD: Removing an item from the middle causes recreation
variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
}

# Removing us-west-2b forces recreation of us-west-2c (index changes)
```

#### ✅ Map-Based Resources
```hcl
variable "iam_users" {
  type = map(object({
    groups = list(string)
    path   = optional(string, "/")
  }))
  default = {
    alice = { groups = ["developers"] }
    bob   = { groups = ["ops", "developers"], path = "/admin/" }
  }
}

resource "aws_iam_user" "users" {
  for_each = var.iam_users

  name = each.key
  path = each.value.path
}

resource "aws_iam_user_group_membership" "users" {
  for_each = var.iam_users

  user   = aws_iam_user.users[each.key].name
  groups = each.value.groups
}

# Access: aws_iam_user.users["alice"]
```

#### ✅ Complex Conditional with For Expression
```hcl
variable "instances" {
  type = map(object({
    instance_type = string
    enabled       = bool
    monitoring    = optional(bool, false)
  }))
}

resource "aws_instance" "app" {
  for_each = { for k, v in var.instances : k => v if v.enabled }

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = each.value.instance_type
  monitoring             = each.value.monitoring

  tags = { Name = each.key }
}
```

---

## Modern Terraform Features

### Moved Blocks (1.1+)

Refactor resource addresses without destroying and recreating resources.

```hcl
# Old code
resource "aws_instance" "web_server" {
  ami           = "ami-12345678"
  instance_type = "t3.micro"
}

# New code (after refactoring)
resource "aws_instance" "web" {
  ami           = "ami-12345678"
  instance_type = "t3.micro"
}

moved {
  from = aws_instance.web_server
  to   = aws_instance.web
}

# Terraform will update state without destroying the instance
```

#### Moved with Module Refactoring
```hcl
# Moving resource into a module
moved {
  from = aws_s3_bucket.logs
  to   = module.logging.aws_s3_bucket.logs
}

# Moving resource between modules
moved {
  from = module.old_vpc.aws_vpc.main
  to   = module.network.aws_vpc.main
}

# Moving with for_each
moved {
  from = aws_subnet.public[0]
  to   = aws_subnet.public["us-west-2a"]
}
```

### Optional Object Attributes (1.3+)

Define optional attributes with defaults in complex object types.

```hcl
variable "server_config" {
  type = object({
    name          = string
    instance_type = string
    monitoring    = optional(bool, false)
    backup_config = optional(object({
      enabled   = bool
      retention = optional(number, 7)
      schedule  = optional(string, "0 2 * * *")
    }), {
      enabled   = false
      retention = 7
      schedule  = "0 2 * * *"
    })
  })

  description = "Server configuration with optional attributes"
}

# Usage - minimal required fields
server_config = {
  name          = "web-server"
  instance_type = "t3.micro"
  # monitoring defaults to false
  # backup_config defaults to disabled
}

# Usage - with overrides
server_config = {
  name          = "db-server"
  instance_type = "r5.large"
  monitoring    = true
  backup_config = {
    enabled   = true
    retention = 30
    # schedule defaults to "0 2 * * *"
  }
}
```

#### Complex Nested Optionals
```hcl
variable "database_config" {
  type = object({
    engine         = string
    engine_version = string
    instance_class = string

    storage = optional(object({
      allocated     = optional(number, 20)
      type          = optional(string, "gp3")
      iops          = optional(number)
      encrypted     = optional(bool, true)
    }), {})

    backup = optional(object({
      retention_period      = optional(number, 7)
      backup_window         = optional(string, "03:00-04:00")
      maintenance_window    = optional(string, "Mon:04:00-Mon:05:00")
      skip_final_snapshot   = optional(bool, false)
    }), {})

    monitoring = optional(object({
      enabled             = optional(bool, true)
      interval            = optional(number, 60)
      performance_insights = optional(bool, false)
    }), {})
  })
}
```

### Check Blocks (1.5+)

Continuous validation and assertion checks that run on every plan/apply.

```hcl
# Health check validation
check "api_health" {
  data "http" "api_endpoint" {
    url = "https://${aws_lb.main.dns_name}/health"

    request_headers = {
      Accept = "application/json"
    }
  }

  assert {
    condition     = data.http.api_endpoint.status_code == 200
    error_message = "API health check failed: ${data.http.api_endpoint.status_code}"
  }
}

# Database connectivity check
check "database_connectivity" {
  data "http" "db_check" {
    url = "https://api.example.com/db-status"
  }

  assert {
    condition     = jsondecode(data.http.db_check.response_body).status == "healthy"
    error_message = "Database is not healthy"
  }
}

# Resource state validation
check "instance_running" {
  assert {
    condition     = aws_instance.web.instance_state == "running"
    error_message = "EC2 instance is not in running state"
  }
}

# Configuration consistency
check "subnet_distribution" {
  assert {
    condition     = length(aws_subnet.private) >= 2
    error_message = "Must have at least 2 private subnets for high availability"
  }
}
```

### Import Blocks (1.5+)

Declare imports in configuration for reproducibility.

```hcl
# Import existing AWS resources
import {
  to = aws_instance.web
  id = "i-1234567890abcdef0"
}

import {
  to = aws_vpc.legacy
  id = "vpc-0123456789abcdef0"
}

# Import with for_each
import {
  for_each = toset(["sg-111", "sg-222", "sg-333"])
  to       = aws_security_group.imported[each.key]
  id       = each.key
}

# Generate import config from state
# terraform plan -generate-config-out=imported.tf
```

### Removed Blocks (1.7+)

Remove resources from Terraform state without destroying them.

```hcl
# Remove from state but keep in cloud
removed {
  from = aws_instance.legacy

  lifecycle {
    destroy = false
  }
}

# Remove multiple resources
removed {
  from = aws_security_group.old[*]

  lifecycle {
    destroy = false
  }
}

# Use case: Migrating resource to another Terraform state
removed {
  from = module.database.aws_db_instance.main

  lifecycle {
    destroy = false
  }
}
# Then import to new state file elsewhere
```

### Ephemeral Resources (1.10+)

Resources that exist only during plan/apply, never stored in state. Perfect for secrets and temporary credentials.

```hcl
# Fetch secret during apply, never store in state
ephemeral "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db.id
}

resource "aws_db_instance" "main" {
  identifier        = "mydb"
  engine            = "postgres"
  instance_class    = "db.t3.micro"

  username = "admin"
  password = ephemeral.aws_secretsmanager_secret_version.db_password.secret_string
}

# Temporary credentials
ephemeral "aws_sts_assume_role" "deploy" {
  role_arn = "arn:aws:iam::123456789012:role/deploy"
}

provider "kubernetes" {
  host  = data.aws_eks_cluster.main.endpoint
  token = ephemeral.aws_sts_assume_role.deploy.credentials.session_token
}
```

### Write-Only Arguments (1.11+)

Sensitive arguments that are set but never read back from state.

```hcl
resource "aws_db_instance" "main" {
  identifier     = "production-db"
  engine         = "postgres"
  instance_class = "db.r5.large"

  username = "admin"
  password = var.db_password  # write-only: never stored in state

  # Password changes don't trigger replacement
  lifecycle {
    ignore_changes = [password]
  }
}

# TLS private keys
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096

  # Private key is write-only
  # Use with ephemeral or output with sensitive = true
}

output "private_key" {
  value     = tls_private_key.example.private_key_pem
  sensitive = true  # Never shown in logs
}
```

---

## Variable Validation Patterns

### Basic Validation
```hcl
variable "environment" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "instance_type" {
  type = string

  validation {
    condition     = can(regex("^t3\\.(nano|micro|small|medium)$", var.instance_type))
    error_message = "Instance type must be t3.nano, t3.micro, t3.small, or t3.medium."
  }
}
```

### Advanced Validation
```hcl
variable "cidr_block" {
  type = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "tags" {
  type = map(string)

  validation {
    condition     = contains(keys(var.tags), "Environment")
    error_message = "Tags must include 'Environment' key."
  }
}

variable "backup_retention" {
  type = number

  validation {
    condition     = var.backup_retention >= 7 && var.backup_retention <= 35
    error_message = "Backup retention must be between 7 and 35 days."
  }
}

variable "subnets" {
  type = list(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))

  validation {
    condition = alltrue([
      for s in var.subnets : can(cidrhost(s.cidr_block, 0))
    ])
    error_message = "All subnet CIDR blocks must be valid."
  }

  validation {
    condition     = length(var.subnets) >= 2
    error_message = "Must define at least 2 subnets for high availability."
  }
}
```

---

## Dynamic Blocks

### Basic Dynamic Block
```hcl
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules

    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }
}

variable "ingress_rules" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS"
    }
  ]
}
```

### Nested Dynamic Blocks
```hcl
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  dynamic "default_action" {
    for_each = var.enable_redirect ? [1] : []

    content {
      type = "redirect"

      redirect {
        protocol    = "HTTPS"
        port        = "443"
        status_code = "HTTP_301"
      }
    }
  }
}
```

### Conditional Dynamic Blocks
```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  # Only create block devices if specified
  dynamic "ebs_block_device" {
    for_each = var.ebs_volumes

    content {
      device_name = ebs_block_device.value.device_name
      volume_size = ebs_block_device.value.volume_size
      volume_type = ebs_block_device.value.volume_type
      encrypted   = lookup(ebs_block_device.value, "encrypted", true)
    }
  }

  # Conditional network interfaces
  dynamic "network_interface" {
    for_each = var.network_interfaces

    content {
      network_interface_id = network_interface.value.id
      device_index         = network_interface.key
    }
  }
}
```

---

## Naming Conventions

### Resources
```hcl
# ✅ Good: snake_case
resource "aws_instance" "web_server" {}
resource "aws_security_group" "allow_http_https" {}
resource "aws_s3_bucket" "application_logs" {}

# ❌ Bad: CamelCase or kebab-case
resource "aws_instance" "WebServer" {}
resource "aws_instance" "web-server" {}
```

### Variables
```hcl
# ✅ Good: snake_case, descriptive
variable "vpc_cidr_block" {
  type = string
}

variable "enable_dns_hostnames" {
  type = bool
}

variable "max_retry_attempts" {
  type = number
}

# ❌ Bad: unclear, abbreviated
variable "vcb" {}
variable "dns" {}
variable "max" {}
```

### Outputs
```hcl
# ✅ Good: snake_case, clear purpose
output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = values(aws_subnet.private)[*].id
}

output "load_balancer_dns_name" {
  value = aws_lb.main.dns_name
}

# ❌ Bad: unclear
output "id" {}
output "subnets" {}
output "dns" {}
```

### Locals
```hcl
# ✅ Good: snake_case, grouped logically
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project_name
  }

  az_count = min(length(data.aws_availability_zones.available.names), 3)

  security_group_rules = {
    http  = { port = 80, protocol = "tcp" }
    https = { port = 443, protocol = "tcp" }
    ssh   = { port = 22, protocol = "tcp" }
  }
}

# ❌ Bad: unclear, mixed conventions
locals {
  tags = {}
  az   = 3
  sgr  = {}
}
```

### Files
```hcl
# ✅ Good: descriptive, organized
main.tf                 # Primary resources
variables.tf            # Input variables
outputs.tf              # Output values
versions.tf             # Terraform and provider versions
backend.tf              # Backend configuration
data-sources.tf         # Data sources
security-groups.tf      # Security group resources
networking.tf           # Network resources

# ✅ Good: snake_case alternative
main.tf
variables.tf
outputs.tf
iam_roles.tf
s3_buckets.tf

# ❌ Bad: unclear, inconsistent
stuff.tf
resources.tf
my-file.tf
file1.tf
```

---

## Common Anti-Patterns

### ❌ Hardcoded Values
```hcl
# BAD
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"  # Hardcoded AMI
  instance_type = "t3.medium"              # Hardcoded size
  subnet_id     = "subnet-12345678"        # Hardcoded subnet
}
```

### ✅ Parameterized Configuration
```hcl
# GOOD
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[0].id
}
```

### ❌ Inline Resource Creation
```hcl
# BAD: Creates implicit resource
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web.id]
}
```

### ✅ Explicit Resource Creation
```hcl
# GOOD: Explicit, manageable
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "web_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]
}
```

### ❌ String Interpolation Only
```hcl
# BAD: Unnecessary string interpolation
resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-logs"
}

# BAD: Forces string conversion
resource "aws_instance" "web" {
  tags = {
    Count = "${var.instance_count}"
  }
}
```

### ✅ Direct References
```hcl
# GOOD: Direct reference when possible
resource "aws_s3_bucket" "logs" {
  bucket = var.bucket_name
}

# GOOD: Use string interpolation only when needed
resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-${var.environment}-logs"
}

# GOOD: Preserve types
resource "aws_instance" "web" {
  tags = {
    Count = var.instance_count
  }
}
```

### ❌ Overusing Depends_On
```hcl
# BAD: Unnecessary explicit dependency
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id

  depends_on = [aws_vpc.main]  # Redundant
}
```

### ✅ Implicit Dependencies
```hcl
# GOOD: Implicit dependency via reference
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

# Use depends_on only for non-obvious dependencies
resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn

  # Necessary: Ensure role exists before function tries to assume it
  depends_on = [aws_iam_role.lambda]
}
```

### ❌ Ignoring State Management
```hcl
# BAD: No lifecycle rules for sensitive operations
resource "aws_db_instance" "main" {
  identifier     = "production-db"
  engine         = "postgres"
  instance_class = "db.r5.large"

  # Dangerous: DB can be accidentally destroyed
}
```

### ✅ Proper Lifecycle Management
```hcl
# GOOD: Protect critical resources
resource "aws_db_instance" "main" {
  identifier     = "production-db"
  engine         = "postgres"
  instance_class = "db.r5.large"

  lifecycle {
    prevent_destroy       = true
    create_before_destroy = true
    ignore_changes        = [password]
  }

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.identifier}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
}
```

### ❌ Mixing Concerns
```hcl
# BAD: Everything in one file
# main.tf (5000 lines)
terraform { ... }
provider "aws" { ... }
resource "aws_vpc" { ... }
resource "aws_instance" { ... }
resource "aws_rds_instance" { ... }
resource "kubernetes_deployment" { ... }
# ... 4900 more lines
```

### ✅ Organized Structure
```hcl
# GOOD: Separated by concern
# versions.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers { ... }
}

# networking.tf
resource "aws_vpc" "main" { ... }
resource "aws_subnet" "public" { ... }

# compute.tf
resource "aws_instance" "web" { ... }
resource "aws_autoscaling_group" "app" { ... }

# database.tf
resource "aws_db_instance" "main" { ... }

# kubernetes.tf
resource "kubernetes_deployment" "app" { ... }
```

---

## Summary

Key principles for high-quality Terraform/OpenTofu code:

1. **Use consistent block ordering** for readability
2. **Prefer for_each over count** for list-based resources
3. **Leverage modern features** (moved blocks, optional attributes, check blocks)
4. **Validate inputs** with validation blocks
5. **Use dynamic blocks** for repeated nested blocks
6. **Follow naming conventions** (snake_case everywhere)
7. **Avoid anti-patterns** (hardcoding, over-depends_on, mixed concerns)
8. **Manage lifecycle** appropriately for critical resources
9. **Organize files** by logical domains
10. **Document everything** with descriptions and comments

---

*Last Updated: 2026-02-05*
