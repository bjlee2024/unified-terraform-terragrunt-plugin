# Terraform/Terragrunt Quick Reference

One-page cheat sheet for the most common patterns and commands.

## Decision Matrix

| Question | Answer | Use |
|----------|--------|-----|
| Single module? | Yes | **Terraform** |
| Multiple environments? | Yes | **Terragrunt** |
| Need DRY config? | Yes | **Terragrunt** |
| Simple project? | Yes | **Terraform** |
| Complex dependencies? | Yes | **Terragrunt Catalog** |

## Terraform Quick Commands

```bash
# Initialize
terraform init

# Format code
terraform fmt -recursive

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Destroy
terraform destroy

# Test
terraform test

# Import existing resource
terraform import aws_instance.example i-1234567890abcdef0

# State operations
terraform state list
terraform state show aws_instance.example
terraform state mv aws_instance.old aws_instance.new
terraform state rm aws_instance.unused

# Workspace operations
terraform workspace list
terraform workspace new dev
terraform workspace select dev

# Output values
terraform output
terraform output -json vpc_id
```

## Terragrunt Quick Commands

```bash
# Initialize
terragrunt init

# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy
terragrunt destroy

# Plan all (with dependencies)
terragrunt run-all plan

# Apply all (with dependencies)
terragrunt run-all apply

# Output values
terragrunt output
terragrunt output -json

# Dependency graph
terragrunt graph-dependencies

# Validate configuration
terragrunt validate

# Show inputs
terragrunt render-json

# Update module sources
terragrunt init -upgrade

# Force unlock state
terragrunt force-unlock LOCK_ID
```

## Common Terraform Patterns

### Variable with Validation
```hcl
variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}
```

### for_each Loop
```hcl
resource "aws_subnet" "main" {
  for_each = var.subnets

  vpc_id     = aws_vpc.main.id
  cidr_block = each.value.cidr

  tags = {
    Name = each.key
  }
}
```

### Conditional Resource
```hcl
resource "aws_nat_gateway" "main" {
  count = var.enable_nat ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
}
```

### Dynamic Block
```hcl
resource "aws_security_group" "main" {
  name   = "example"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidrs
    }
  }
}
```

### Local Values
```hcl
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  subnet_ids = [for s in aws_subnet.main : s.id]
}
```

### Output with Description
```hcl
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}
```

## Common Terragrunt Patterns

### Root Configuration
```hcl
# root.hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "terraform-state-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region}"
}
EOF
}
```

### Dependency
```hcl
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-mock"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  vpc_id = dependency.vpc.outputs.vpc_id
}
```

### Values Pattern
```hcl
# In unit
locals {
  default_values = {
    versioning_enabled = true
  }
  values = merge(local.default_values, try(var.values, {}))
}

variable "values" {
  type    = any
  default = {}
}

# In stack
unit "s3" {
  source = "../../units/s3"
  values = {
    bucket_name = "my-bucket"
  }
}
```

### Include Parent
```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}
```

### Read Parent Config
```hcl
locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  project = local.common.locals.project
}
```

## Terraform Test Patterns

### Basic Test
```hcl
run "basic_test" {
  command = plan

  variables = {
    name = "test-vpc"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR should be 10.0.0.0/16"
  }
}
```

### Mock Provider
```hcl
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
}
```

### Validation Test
```hcl
run "invalid_input" {
  command = plan

  variables = {
    name = ""  # Invalid
  }

  expect_failures = [
    var.name,
  ]
}
```

## Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| State lock timeout | Another operation in progress | `terraform force-unlock LOCK_ID` |
| Cycle error | Circular dependency | Review depends_on, break cycle |
| Invalid count | Count depends on computed value | Use for_each instead |
| Resource not found | Resource doesn't exist | Check if resource was created |
| Auth error | Invalid AWS credentials | Check AWS_PROFILE or credentials |
| Backend init failed | Backend config changed | Run `terraform init -reconfigure` |

## Security Checklist

- [ ] No hardcoded secrets in code
- [ ] Remote state encrypted and locked
- [ ] Sensitive outputs marked as `sensitive = true`
- [ ] IAM roles use least privilege
- [ ] Security groups use minimal ports
- [ ] Resources use encryption at rest
- [ ] Resources use encryption in transit
- [ ] Backup and retention policies configured
- [ ] Logging enabled on critical resources
- [ ] Tags applied for cost tracking

## Performance Tips

1. **Use -target for large states** - `terraform plan -target=aws_instance.example`
2. **Enable plugin cache** - Set `TF_PLUGIN_CACHE_DIR`
3. **Use -parallelism** - `terraform apply -parallelism=20`
4. **Upgrade providers** - `terraform init -upgrade`
5. **Use terraform.lock.hcl** - Commit dependency lock file
6. **Split large states** - Use workspaces or separate roots
7. **Mock dependencies** - Use mock_outputs in Terragrunt
8. **Cache .terragrunt-cache** - Reuse downloaded modules

## Version Constraints

```hcl
# Exact version
version = "5.0.0"

# Minimum version
version = ">= 5.0.0"

# Pessimistic constraint (recommended)
version = "~> 5.0"      # >= 5.0, < 6.0
version = "~> 5.0.0"    # >= 5.0.0, < 5.1.0

# Multiple constraints
version = ">= 5.0, < 6.0"
```

## State Management

```bash
# List resources in state
terraform state list

# Show resource details
terraform state show aws_instance.example

# Move resource
terraform state mv aws_instance.old aws_instance.new

# Remove resource from state (doesn't delete)
terraform state rm aws_instance.example

# Import existing resource
terraform import aws_instance.example i-1234567890abcdef0

# Pull remote state
terraform state pull > terraform.tfstate.backup

# Push state (dangerous!)
terraform state push terraform.tfstate
```

## Environment Variables

```bash
# AWS credentials
export AWS_PROFILE=myprofile
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx

# Terraform behavior
export TF_LOG=DEBUG              # Enable debug logging
export TF_LOG_PATH=terraform.log # Log to file
export TF_INPUT=false            # Disable interactive prompts
export TF_PLUGIN_CACHE_DIR=~/.terraform.d/plugin-cache

# Terragrunt behavior
export TERRAGRUNT_DOWNLOAD=./.terragrunt-cache
export TERRAGRUNT_SOURCE=/path/to/local/modules
export TERRAGRUNT_DEBUG=true
```

## Useful Functions

```hcl
# String manipulation
lower(string)                    # "HELLO" -> "hello"
upper(string)                    # "hello" -> "HELLO"
trimspace(string)                # "  hello  " -> "hello"
split(",", string)               # "a,b,c" -> ["a", "b", "c"]
join(",", list)                  # ["a", "b", "c"] -> "a,b,c"
replace(string, search, replace) # Replace substring

# Collection operations
length(list)                     # Number of items
element(list, index)             # Get item at index
contains(list, value)            # Check if value exists
merge(map1, map2)                # Merge maps
keys(map)                        # Get map keys
values(map)                      # Get map values
flatten(list)                    # Flatten nested lists
distinct(list)                   # Remove duplicates
sort(list)                       # Sort list

# Type conversion
tostring(value)                  # Convert to string
tonumber(value)                  # Convert to number
tobool(value)                    # Convert to boolean
tolist(value)                    # Convert to list
tomap(value)                     # Convert to map
toset(value)                     # Convert to set

# Conditional
condition ? true_val : false_val # Ternary operator

# Encoding
jsonencode(value)                # Encode as JSON
yamlencode(value)                # Encode as YAML
base64encode(string)             # Base64 encode
base64decode(string)             # Base64 decode

# Filesystem
file(path)                       # Read file contents
fileexists(path)                 # Check if file exists
fileset(path, pattern)           # Find files matching pattern

# IP Network
cidrhost(prefix, hostnum)        # Get IP from CIDR
cidrsubnet(prefix, newbits, num) # Calculate subnet
```

## Common Terraform Block Patterns

```hcl
# Terraform settings
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# Provider configuration
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy = "Terraform"
    }
  }
}

# Data source
data "aws_ami" "latest" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
}

# Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"
}
```

## Links

- [Terraform Documentation](https://www.terraform.io/docs)
- [Terraform Registry](https://registry.terraform.io/)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
