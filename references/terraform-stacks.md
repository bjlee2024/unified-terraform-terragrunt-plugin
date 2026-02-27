# Terraform Stacks Reference

## Overview

Terraform Stacks is a native orchestration layer for managing deployments across multiple environments, regions, and accounts within a single configuration. It uses Stack Language (a separate HCL dialect) to define components and deployments.

**Key Distinction**: Stack Language is NOT regular Terraform HCL. Files use `.tfcomponent.hcl` and `.tfdeploy.hcl` extensions and have different syntax rules.

## Core Concepts

### Stack

A stack is the top-level container that defines:
- Reusable components (infrastructure modules)
- Deployments (instantiations of components)
- Deployment orchestration (ordering, grouping, approvals)

**File Structure**:
```
my-stack/
├── components/
│   ├── network.tfcomponent.hcl
│   └── compute.tfcomponent.hcl
├── deployments/
│   ├── production.tfdeploy.hcl
│   └── staging.tfdeploy.hcl
└── modules/
    └── vpc/
        ├── main.tf
        └── variables.tf
```

### Component

A component is a reusable infrastructure pattern defined in `.tfcomponent.hcl` files. Components:
- Reference Terraform modules or configurations
- Define input variables and outputs
- Configure providers
- Can be deployed multiple times with different configurations

**NOT the same as Terraform modules** - components wrap modules with Stack Language constructs.

### Deployment

A deployment is a specific instantiation of a component with concrete values, defined in `.tfdeploy.hcl` files. Each deployment:
- Targets a specific environment (production, staging, etc.)
- Provides values for component variables
- Configures authentication (OIDC identity tokens)
- Has independent state

**Limit**: Maximum 20 deployments per stack (can be increased to 100 in HCP Terraform Premium).

## Stack Language Syntax

### Component Configuration (.tfcomponent.hcl)

#### Variable Block

```hcl
variable "region" {
  type        = string
  description = "AWS region for deployment"
  # Note: validation blocks are NOT supported in Stack Language
}

variable "instance_count" {
  type    = number
  default = 1
}

variable "tags" {
  type = map(string)
  default = {
    managed_by = "terraform-stacks"
  }
}
```

**Differences from Terraform**:
- `type` is REQUIRED (not optional)
- No `validation` blocks
- No `sensitive` or `nullable` attributes

#### Required Providers Block

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
  random = {
    source  = "hashicorp/random"
    version = "~> 3.5"
  }
}
```

**Purpose**: Declares providers needed by this component (similar to `terraform.required_providers` in regular Terraform).

#### Provider Block

```hcl
provider "aws" "configurations" {
  for_each = var.regions

  config {
    region = each.value

    assume_role {
      role_arn = var.role_arn
    }

    default_tags {
      tags = var.common_tags
    }
  }
}

provider "aws" "single" {
  config {
    region = var.region
  }
}
```

**Key Features**:
- Supports `for_each` for multi-region/multi-account patterns
- Configuration wrapped in `config` block (NOT at top level like Terraform)
- No `alias` attribute (use block label instead: `provider "aws" "us_east"`)

#### Component Block

```hcl
component "vpc" {
  source = "./modules/vpc"

  inputs = {
    cidr_block           = var.vpc_cidr
    availability_zones   = var.azs
    enable_nat_gateway   = true
    single_nat_gateway   = var.environment != "production"
    tags                 = var.tags
  }

  providers = {
    aws = provider.aws.configurations
  }
}

component "compute" {
  source = "./modules/ec2-instances"

  inputs = {
    vpc_id            = component.vpc.vpc_id
    subnet_ids        = component.vpc.private_subnet_ids
    instance_type     = var.instance_type
    ami               = var.ami_id
  }

  providers = {
    aws = provider.aws.configurations
  }
}
```

**Key Points**:
- `source` points to local path or module registry
- `inputs` block maps to module variables
- `providers` block assigns provider configurations
- Component dependencies inferred from `component.X.output` references

**Dependency Inference**: Terraform Stacks automatically determines that `compute` depends on `vpc` because it references `component.vpc.vpc_id`.

#### Output Block

```hcl
output "vpc_id" {
  type        = string
  description = "VPC ID created by this component"
  value       = component.vpc.vpc_id
}

output "endpoint_url" {
  type  = string
  value = component.compute.load_balancer_dns
}
```

**Differences from Terraform**:
- `type` is REQUIRED
- No `sensitive` attribute
- Used to expose component values to deployments

#### Locals Block

```hcl
locals {
  environment = var.environment
  project     = var.project_name

  common_tags = {
    Environment = local.environment
    Project     = local.project
    ManagedBy   = "terraform-stacks"
  }

  region_configs = {
    for region in var.regions : region => {
      cidr = cidrsubnet(var.base_cidr, 4, index(var.regions, region))
    }
  }
}
```

**Usage**: Same as Terraform locals, for intermediate values.

#### Removed Block

```hcl
removed {
  source = "./modules/legacy-component"

  lifecycle {
    destroy = false
  }
}
```

**Purpose**: Handles component removal from stack configuration while preserving infrastructure.

### Deployment Configuration (.tfdeploy.hcl)

#### Identity Token Block

```hcl
identity_token "aws" {
  audience = ["aws.workload.identity"]
}
```

**Purpose**: Configures OIDC authentication for dynamic credentials. HCP Terraform exchanges this token for cloud provider credentials.

**Supported Providers**:
- AWS (via IAM OIDC)
- Azure (via Workload Identity)
- GCP (via Workload Identity Federation)

#### Locals Block

```hcl
locals {
  regions = ["us-east-1", "us-west-2", "eu-west-1"]

  production_config = {
    instance_type  = "t3.large"
    instance_count = 3
    backup_enabled = true
  }

  staging_config = {
    instance_type  = "t3.small"
    instance_count = 1
    backup_enabled = false
  }
}
```

#### Deployment Block

```hcl
deployment "production_us_east" {
  inputs = {
    region          = "us-east-1"
    environment     = "production"
    vpc_cidr        = "10.0.0.0/16"
    instance_type   = "t3.large"
    instance_count  = 3

    role_arn = "arn:aws:iam::123456789012:role/TerraformStacksRole"
  }
}

deployment "production_multi_region" {
  inputs = {
    regions = {
      "us-east-1" = { cidr = "10.0.0.0/16" }
      "us-west-2" = { cidr = "10.1.0.0/16" }
      "eu-west-1" = { cidr = "10.2.0.0/16" }
    }
    environment = "production"
  }
}

deployment "staging" {
  inputs = {
    region          = "us-east-1"
    environment     = "staging"
    vpc_cidr        = "10.100.0.0/16"
    instance_type   = "t3.small"
    instance_count  = 1
  }
}
```

**Key Points**:
- Each deployment is independent with separate state
- Maximum 20 per stack (100 in HCP Terraform Premium)
- Input values provided at deployment time (not component time)

#### Deployment Group Block (Premium Feature)

```hcl
deployment_group "production_all_regions" {
  deployments = [
    deployment.production_us_east,
    deployment.production_us_west,
    deployment.production_eu_west
  ]
}

deployment_group "staging_environments" {
  deployments = [
    deployment.staging_us,
    deployment.staging_eu
  ]
}
```

**Purpose**: Logical grouping of deployments for orchestration. Requires HCP Terraform Premium.

#### Deployment Auto-Approve Block

```hcl
deployment_auto_approve "staging_environments" {
  deployment_group = deployment_group.staging_environments

  conditions = [
    {
      type = "plan_status"
      value = "no_changes"
    }
  ]
}

deployment_auto_approve "non_production" {
  deployment_group = deployment_group.all_non_prod

  conditions = [
    {
      type = "resource_changes"
      max_creates = 10
      max_updates = 5
      max_deletes = 0
    }
  ]
}
```

**Purpose**: Automate approvals for deployments meeting specific conditions (no changes, small changes, etc.).

#### Publish Output Block

```hcl
publish_output "vpc_endpoints" {
  value = {
    for k, v in deployment : k => v.outputs.vpc_id
  }
}

publish_output "load_balancer_urls" {
  value = {
    production = deployment.production.outputs.endpoint_url
    staging    = deployment.staging.outputs.endpoint_url
  }
}
```

**Purpose**: Expose deployment outputs for consumption by other stacks or external systems.

#### Upstream Input Block (Linked Stacks)

```hcl
upstream_input "network_stack" {
  stack = "networking-foundation"

  outputs = {
    vpc_id        = "vpc_id"
    subnet_ids    = "private_subnet_ids"
    security_group = "default_security_group_id"
  }
}

deployment "app_deployment" {
  inputs = {
    vpc_id            = upstream.network_stack.vpc_id
    subnet_ids        = upstream.network_stack.subnet_ids
    security_group_id = upstream.network_stack.security_group

    app_config = var.app_configuration
  }
}
```

**Purpose**: Reference outputs from other stacks, creating dependencies between stacks.

## Common Patterns

### Multi-Region Deployment with for_each

**Component** (`network.tfcomponent.hcl`):
```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
}

variable "regions" {
  type = map(object({
    cidr               = string
    availability_zones = list(string)
  }))
}

variable "role_arn" {
  type = string
}

provider "aws" "regional" {
  for_each = var.regions

  config {
    region = each.key

    assume_role {
      role_arn = var.role_arn
    }
  }
}

component "vpc" {
  for_each = var.regions

  source = "./modules/vpc"

  inputs = {
    cidr_block         = each.value.cidr
    availability_zones = each.value.availability_zones
  }

  providers = {
    aws = provider.aws.regional[each.key]
  }
}

output "vpc_ids" {
  type = map(string)
  value = {
    for k, v in component.vpc : k => v.vpc_id
  }
}
```

**Deployment** (`production.tfdeploy.hcl`):
```hcl
identity_token "aws" {
  audience = ["aws.workload.identity"]
}

deployment "production_global" {
  inputs = {
    regions = {
      "us-east-1" = {
        cidr               = "10.0.0.0/16"
        availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
      }
      "us-west-2" = {
        cidr               = "10.1.0.0/16"
        availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
      }
      "eu-west-1" = {
        cidr               = "10.2.0.0/16"
        availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
      }
    }
    role_arn = "arn:aws:iam::123456789012:role/TerraformStacksRole"
  }
}
```

### Component Dependencies (Automatic Inference)

```hcl
# network.tfcomponent.hcl
component "vpc" {
  source = "./modules/vpc"
  inputs = { cidr_block = var.vpc_cidr }
}

output "vpc_id" {
  type  = string
  value = component.vpc.vpc_id
}

output "private_subnet_ids" {
  type  = list(string)
  value = component.vpc.private_subnet_ids
}

# compute.tfcomponent.hcl
component "app_servers" {
  source = "./modules/ec2-cluster"

  inputs = {
    vpc_id     = component.vpc.vpc_id              # Implicit dependency
    subnet_ids = component.vpc.private_subnet_ids  # Implicit dependency
  }
}

component "load_balancer" {
  source = "./modules/alb"

  inputs = {
    vpc_id      = component.vpc.vpc_id
    target_arns = component.app_servers.instance_arns  # Dependency on app_servers
  }
}
```

**Execution Order**: Stacks automatically determines:
1. `vpc` component (no dependencies)
2. `app_servers` component (depends on `vpc`)
3. `load_balancer` component (depends on `vpc` and `app_servers`)

## CLI Commands

### Initialize and Validate

```bash
# Initialize stack (download providers and modules)
terraform stacks init

# Validate stack configuration
terraform stacks validate

# Validate specific deployment
terraform stacks validate -deployment=production
```

### Lock Provider Versions

```bash
# Generate provider lock file for all deployments
terraform stacks providers-lock

# Lock providers for specific platforms
terraform stacks providers-lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64 \
  -platform=windows_amd64
```

**Output**: Creates `.terraform.lock.hcl` file with provider version hashes.

### Plan

```bash
# Plan all deployments in stack
terraform stacks plan

# Plan specific deployment
terraform stacks plan -deployment=production_us_east

# Plan deployment group (Premium)
terraform stacks plan -deployment-group=production_all_regions

# Plan with output file
terraform stacks plan -out=tfplan

# Plan with parallelism control
terraform stacks plan -parallelism=10
```

### Apply

```bash
# Apply all deployments
terraform stacks apply

# Apply specific deployment
terraform stacks apply -deployment=staging

# Apply from plan file
terraform stacks apply tfplan

# Auto-approve (skip interactive approval)
terraform stacks apply -auto-approve

# Apply deployment group
terraform stacks apply -deployment-group=staging_environments
```

### Destroy

```bash
# Destroy specific deployment
terraform stacks destroy -deployment=staging

# Destroy all deployments in stack
terraform stacks destroy

# Auto-approve destroy
terraform stacks destroy -auto-approve
```

### Outputs

```bash
# Show outputs for all deployments
terraform stacks output

# Show outputs for specific deployment
terraform stacks output -deployment=production

# JSON output format
terraform stacks output -json
```

### State Management

```bash
# List resources in deployment
terraform stacks state list -deployment=production

# Show specific resource
terraform stacks state show -deployment=production 'aws_vpc.main'

# Move resource between deployments (advanced)
terraform stacks state mv \
  -deployment-source=old_deployment \
  -deployment-target=new_deployment \
  'aws_instance.app' 'aws_instance.app'
```

## Best Practices

### Component Granularity

**Good** - Cohesive components:
```
components/
├── networking.tfcomponent.hcl      # VPC, subnets, routing
├── security.tfcomponent.hcl        # Security groups, NACLs
├── compute.tfcomponent.hcl         # EC2, ASG, launch templates
└── data-storage.tfcomponent.hcl    # RDS, S3, DynamoDB
```

**Bad** - Too granular or too monolithic:
```
components/
├── everything.tfcomponent.hcl      # 1000+ line monolith
└── vpc-subnet-1a.tfcomponent.hcl   # Too specific
```

**Guideline**: Each component should represent a logical unit that changes together.

### Module Compatibility

Modules used with Stacks **MUST NOT** contain provider blocks:

**Compatible Module**:
```hcl
# modules/vpc/main.tf
resource "aws_vpc" "main" {
  cidr_block = var.cidr_block
}
# No provider blocks!
```

**Incompatible Module**:
```hcl
# modules/vpc/main.tf
provider "aws" {
  region = "us-east-1"  # ❌ Will cause errors
}

resource "aws_vpc" "main" {
  cidr_block = var.cidr_block
}
```

**Why**: Stacks manages provider configuration at the component level. Module-level providers conflict with Stack Language provider management.

### Deployment Organization

**Recommended Structure**:
```
deployments/
├── environments/
│   ├── production.tfdeploy.hcl
│   ├── staging.tfdeploy.hcl
│   └── dev.tfdeploy.hcl
├── regions/
│   ├── us-deployments.tfdeploy.hcl
│   └── eu-deployments.tfdeploy.hcl
└── shared.tfdeploy.hcl
```

**Pattern**: Organize by environment, region, or function based on your deployment model.

### Deployment Groups Best Practice

Use deployment groups to:
- Coordinate multi-region rollouts
- Apply changes to environment tiers (dev → staging → production)
- Manage blast radius during updates

**Example**:
```hcl
deployment_group "production_tier_1" {
  deployments = [
    deployment.production_us_east_1a
  ]
}

deployment_group "production_tier_2" {
  deployments = [
    deployment.production_us_west_2a,
    deployment.production_eu_west_1a
  ]

  # Depends on tier 1 completing successfully
  depends_on = [deployment_group.production_tier_1]
}
```

### State Backend Configuration

Stacks **automatically** manages state in HCP Terraform. No backend configuration needed:

```hcl
# ❌ NOT NEEDED - Stacks handles this
terraform {
  backend "remote" {
    organization = "my-org"
  }
}
```

Each deployment gets isolated state automatically.

## Troubleshooting

### Circular Dependencies

**Error**:
```
Error: Cycle detected in component dependencies
  component.app depends on component.database
  component.database depends on component.app
```

**Solution**: Break the cycle with outputs and two-phase deployment:

```hcl
# Phase 1: Create database without app security group
component "database" {
  source = "./modules/rds"
  inputs = {
    vpc_id = component.vpc.vpc_id
  }
}

# Phase 2: Update database security group after app is created
component "database_security_update" {
  source = "./modules/security-group-rule"
  inputs = {
    security_group_id = component.database.security_group_id
    source_sg_id      = component.app.security_group_id
  }
}
```

### Deployment Limit Exceeded

**Error**:
```
Error: Exceeded maximum number of deployments (20)
```

**Solutions**:
1. **Upgrade to Premium**: Increases limit to 100 deployments
2. **Consolidate deployments**: Use `for_each` in components instead of multiple deployments
3. **Split into multiple stacks**: Organize by domain or region

**Example Consolidation**:

Before (20 deployments):
```hcl
deployment "prod_us_east_1" { ... }
deployment "prod_us_west_2" { ... }
deployment "prod_eu_west_1" { ... }
# ... 17 more
```

After (1 deployment with for_each):
```hcl
deployment "production_all_regions" {
  inputs = {
    regions = {
      "us-east-1" = { ... }
      "us-west-2" = { ... }
      "eu-west-1" = { ... }
      # ... all regions
    }
  }
}
```

### Provider Configuration Not Found

**Error**:
```
Error: Provider configuration not found for provider["aws"]
```

**Cause**: Component references provider that wasn't declared in `required_providers`.

**Solution**:
```hcl
# Add to component file
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
}

provider "aws" "main" {
  config {
    region = var.region
  }
}
```

### Component Output Type Mismatch

**Error**:
```
Error: Output value type does not match declared type
  Expected: string
  Got: list(string)
```

**Solution**: Ensure output type matches actual value:

```hcl
# If module outputs list
output "subnet_ids" {
  type  = list(string)  # Match actual type
  value = component.vpc.private_subnet_ids
}

# If you need string, convert it
output "first_subnet_id" {
  type  = string
  value = component.vpc.private_subnet_ids[0]
}
```

### Upstream Stack Not Found

**Error**:
```
Error: Upstream stack "network-foundation" not found
```

**Cause**: Referenced stack doesn't exist or has different name.

**Solution**: Verify stack name in HCP Terraform and ensure it's published:

```bash
# List available stacks
terraform stacks list

# Verify upstream stack outputs are published
terraform stacks output -stack=network-foundation
```

## Additional Resources

- [Terraform Stacks Documentation](https://developer.hashicorp.com/terraform/language/stacks)
- [Stack Language Specification](https://developer.hashicorp.com/terraform/language/stacks/syntax)
- [HCP Terraform Stacks Guide](https://developer.hashicorp.com/terraform/cloud-docs/stacks)
