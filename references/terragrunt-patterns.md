# Terragrunt Patterns Reference

Comprehensive guide to Terragrunt patterns, conventions, and best practices for infrastructure as code management.

## Table of Contents

- [Key Concepts](#key-concepts)
- [Naming Conventions](#naming-conventions)
- [Directory Structure](#directory-structure)
- [Configuration Hierarchy](#configuration-hierarchy)
- [Unit Pattern](#unit-pattern)
- [Dependencies](#dependencies)
- [Stack Pattern](#stack-pattern)
- [State Backend](#state-backend)
- [Catalog Scaffolding](#catalog-scaffolding)
- [Version Management](#version-management)
- [Performance Optimization](#performance-optimization)
- [Common Pitfalls](#common-pitfalls)

---

## Key Concepts

### Module Separation

Terragrunt follows a strict separation between **module definitions** (catalog) and **module instantiations** (live):

```
infrastructure-catalog/          # Reusable Terraform modules
  └── modules/
      ├── vpc/
      ├── eks/
      └── rds/

infrastructure-live/             # Environment-specific deployments
  └── prod/
      └── us-east-1/
          ├── vpc/               # Instantiation of catalog vpc module
          └── eks/               # Instantiation of catalog eks module
```

**Why separate repositories?**
- Independent versioning of modules vs deployments
- Clear separation of concerns
- Easier module reusability across projects
- Better access control (module authors vs operators)

### Values Pattern

Terragrunt uses hierarchical configuration files to define environment-specific values:

```
root.hcl          # Organization-wide defaults
  └── account.hcl # Account-level overrides
      └── env.hcl # Environment-level overrides
          └── terragrunt.hcl  # Unit-specific configuration
```

Values cascade down: unit configs override env configs, which override account configs, which override root configs.

### Reference Resolution

Terragrunt resolves references to other units during planning:

```hcl
# Unit A outputs
outputs = {
  vpc_id = "vpc-123456"
}

# Unit B references Unit A
dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  vpc_id = dependency.vpc.outputs.vpc_id  # Resolved to "vpc-123456"
}
```

---

## Naming Conventions

### Repository Names

```
infrastructure-catalog           # Terraform module definitions
infrastructure-live             # Environment deployments
terraform-aws-<service>         # Standalone AWS modules
terraform-gcp-<service>         # Standalone GCP modules
```

### Directory Names

**Catalog structure:**
```
modules/<service>               # Lowercase, hyphen-separated
modules/vpc-peering
modules/eks-cluster
modules/rds-postgres
```

**Live structure:**
```
<account>/<region>/<unit>       # Hierarchical, descriptive
prod/us-east-1/vpc
prod/us-east-1/eks-cluster
staging/eu-west-1/rds-primary
```

### Resource Names

Use consistent naming with environment prefixes:

```hcl
locals {
  name_prefix = "${var.environment}-${var.region_short}"
}

resource "aws_vpc" "main" {
  tags = {
    Name = "${local.name_prefix}-vpc"         # prod-use1-vpc
    Environment = var.environment
    ManagedBy = "terragrunt"
  }
}
```

---

## Directory Structure

### Infrastructure Catalog

```
infrastructure-catalog/
├── README.md
├── modules/
│   ├── networking/
│   │   ├── vpc/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   └── vpc-peering/
│   ├── compute/
│   │   ├── ec2-instance/
│   │   └── eks-cluster/
│   ├── database/
│   │   ├── rds-postgres/
│   │   └── dynamodb-table/
│   └── security/
│       ├── iam-role/
│       └── security-group/
└── examples/
    ├── vpc-with-subnets/
    └── eks-with-addons/
```

**Key principles:**
- Group modules by logical domain (networking, compute, database)
- Each module is self-contained with complete documentation
- Include examples directory for common usage patterns
- Version modules using Git tags (v1.0.0, v2.1.3)

### Infrastructure Live

```
infrastructure-live/
├── root.hcl                    # Root configuration
├── prod/
│   ├── account.hcl             # Production account config
│   ├── us-east-1/
│   │   ├── env.hcl             # Region-specific config
│   │   ├── vpc/
│   │   │   └── terragrunt.hcl  # VPC unit
│   │   ├── eks-cluster/
│   │   │   └── terragrunt.hcl  # EKS unit
│   │   └── rds-primary/
│   │       └── terragrunt.hcl  # RDS unit
│   └── eu-west-1/
│       └── env.hcl
├── staging/
│   ├── account.hcl
│   └── us-west-2/
│       └── env.hcl
└── dev/
    ├── account.hcl
    └── us-west-2/
        └── env.hcl
```

**Key principles:**
- Top-level directories represent AWS accounts or major environments
- Second level represents regions
- Third level represents individual infrastructure units
- Configuration hierarchy allows value inheritance

---

## Configuration Hierarchy

### Root Configuration (root.hcl)

Located at the top of `infrastructure-live`, defines organization-wide defaults:

```hcl
# root.hcl
locals {
  # Organization-wide settings
  organization = "acme-corp"
  domain       = "acme.com"

  # Default tags applied to all resources
  common_tags = {
    Organization = local.organization
    ManagedBy    = "terragrunt"
    Repository   = "infrastructure-live"
  }

  # State backend configuration
  state_bucket_region = "us-east-1"
  state_bucket_name   = "acme-terraform-state"
  dynamodb_table_name = "acme-terraform-locks"
}

# Generate backend configuration for all units
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket         = "${local.state_bucket_name}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "${local.state_bucket_region}"
    encrypt        = true
    dynamodb_table = "${local.dynamodb_table_name}"
  }
}
EOF
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}
EOF
}

# Default inputs available to all units
inputs = {
  organization = local.organization
  default_tags = local.common_tags
}
```

### Account Configuration (account.hcl)

Defines account-level settings (AWS account ID, billing tags, etc.):

```hcl
# prod/account.hcl
locals {
  account_name = "production"
  account_id   = "123456789012"

  # Override default tags with account-specific info
  account_tags = {
    Account     = local.account_name
    AccountId   = local.account_id
    Environment = "prod"
    CostCenter  = "engineering"
  }
}

# Merge root tags with account tags
inputs = merge(
  include.root.locals.common_tags,
  local.account_tags
)
```

### Environment Configuration (env.hcl)

Defines region-specific settings:

```hcl
# prod/us-east-1/env.hcl
locals {
  aws_region   = "us-east-1"
  region_short = "use1"

  # Availability zones for this region
  availability_zones = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c"
  ]

  # CIDR blocks
  vpc_cidr = "10.0.0.0/16"

  # Environment-specific settings
  environment_config = {
    environment      = "prod"
    instance_types   = ["t3.large", "t3.xlarge"]
    enable_monitoring = true
    backup_retention  = 30
  }
}

# Include parent configurations
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

inputs = merge(
  include.root.inputs,
  include.account.inputs,
  {
    aws_region         = local.aws_region
    availability_zones = local.availability_zones
    vpc_cidr          = local.vpc_cidr
  },
  local.environment_config
)
```

---

## Unit Pattern

A **unit** is a single instantiation of a Terraform module. Each unit lives in its own directory with a `terragrunt.hcl` file.

### Basic Unit Structure

```hcl
# prod/us-east-1/vpc/terragrunt.hcl

# Include environment configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
  expose = true  # Makes env.locals available
}

# Point to the module in the catalog
terraform {
  source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc?ref=v1.2.0"
}

# Unit-specific inputs
inputs = {
  vpc_name = "prod-main-vpc"
  vpc_cidr = include.env.locals.vpc_cidr

  # Create subnets in all AZs
  availability_zones = include.env.locals.availability_zones

  # Subnet configuration
  public_subnet_cidrs = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]

  private_subnet_cidrs = [
    "10.0.11.0/24",
    "10.0.12.0/24",
    "10.0.13.0/24"
  ]

  # Enable features
  enable_nat_gateway = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags
  tags = {
    Unit = "vpc"
    Tier = "networking"
  }
}
```

### Unit with Dependencies

```hcl
# prod/us-east-1/eks-cluster/terragrunt.hcl

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

terraform {
  source = "git::git@github.com:acme/infrastructure-catalog.git//modules/eks-cluster?ref=v2.0.1"
}

# Depend on VPC unit
dependency "vpc" {
  config_path = "../vpc"

  # Mock outputs for validation without applying VPC first
  mock_outputs = {
    vpc_id          = "vpc-fake-id"
    private_subnet_ids = ["subnet-fake-1", "subnet-fake-2"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  cluster_name    = "prod-main-eks"
  cluster_version = "1.28"

  # Use VPC outputs
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnet_ids

  # Node group configuration
  node_groups = {
    general = {
      desired_size   = 3
      min_size       = 2
      max_size       = 10
      instance_types = ["t3.large"]
    }
  }

  # OIDC provider for service accounts
  enable_irsa = true

  tags = {
    Unit = "eks-cluster"
    Tier = "compute"
  }
}
```

---

## Dependencies

### Dependency Declaration

```hcl
dependency "<name>" {
  config_path = "<relative-path-to-unit>"

  # Optional: mock outputs for commands that don't need real values
  mock_outputs = {
    output_name = "mock_value"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]

  # Optional: skip output reading entirely for certain commands
  skip_outputs = false
}
```

### Fan-Out Pattern

Multiple units depend on a single upstream unit:

```
        ┌─────────┐
        │   VPC   │
        └────┬────┘
             │
      ┌──────┼──────┐
      │      │      │
   ┌──▼──┐ ┌▼───┐ ┌▼────┐
   │ EKS │ │RDS │ │Redis│
   └─────┘ └────┘ └─────┘
```

All three units reference the same VPC dependency.

### Chain Pattern

Sequential dependencies:

```
┌─────┐    ┌─────┐    ┌──────────┐
│ VPC │───▶│ EKS │───▶│ EKS Auth │
└─────┘    └─────┘    └──────────┘
```

Each unit depends on the previous one in the chain.

### Conditional Dependencies

Use `skip_outputs` to conditionally disable dependency resolution:

```hcl
dependency "vpc" {
  config_path = "../vpc"

  # Skip if running destroy
  skip_outputs = get_env("TG_SKIP_DEPENDENCIES", "false") == "true"

  mock_outputs = {
    vpc_id = "vpc-mock"
  }

  mock_outputs_allowed_terraform_commands = ["validate"]
}

inputs = {
  vpc_id = try(dependency.vpc.outputs.vpc_id, "vpc-default")
}
```

### Reference Resolution in Inputs

Access dependency outputs in various ways:

```hcl
dependency "vpc" {
  config_path = "../vpc"
}

dependency "eks" {
  config_path = "../eks-cluster"
}

inputs = {
  # Direct reference
  vpc_id = dependency.vpc.outputs.vpc_id

  # List manipulation
  subnet_ids = dependency.vpc.outputs.private_subnet_ids
  first_subnet = dependency.vpc.outputs.private_subnet_ids[0]

  # Map access
  cluster_endpoint = dependency.eks.outputs.cluster_endpoint

  # Conditional reference
  vpc_id = try(dependency.vpc.outputs.vpc_id, "default-vpc")

  # Multiple dependencies combined
  networking = {
    vpc_id     = dependency.vpc.outputs.vpc_id
    subnet_ids = dependency.vpc.outputs.private_subnet_ids
  }
}
```

### Provider Generation from Dependencies

Generate provider configuration dynamically from dependency outputs:

```hcl
# prod/us-east-1/eks-addons/terragrunt.hcl

dependency "eks" {
  config_path = "../eks-cluster"
}

generate "provider_k8s" {
  path      = "provider_k8s.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "kubernetes" {
  host                   = "${dependency.eks.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_ca_certificate}")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      "${dependency.eks.outputs.cluster_name}"
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = "${dependency.eks.outputs.cluster_endpoint}"
    cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_ca_certificate}")

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        "${dependency.eks.outputs.cluster_name}"
      ]
    }
  }
}
EOF
}
```

---

## Stack Pattern

Stacks allow you to operate on multiple units as a logical group.

### Stack Configuration (terragrunt.stack.hcl)

```hcl
# prod/us-east-1/terragrunt.stack.hcl

# Stack metadata
stack {
  name        = "prod-us-east-1-core"
  description = "Core infrastructure for production US-East-1"
}

# Units in this stack
unit "vpc" {
  path = "./vpc"
}

unit "eks_cluster" {
  path = "./eks-cluster"

  # This unit depends on vpc
  dependencies = ["vpc"]
}

unit "rds_primary" {
  path = "./rds-primary"
  dependencies = ["vpc"]
}

unit "rds_replica" {
  path = "./rds-replica"
  dependencies = ["rds_primary"]
}

# Stack-level inputs applied to all units
inputs = {
  stack_name = "core-infra"
  deployed_by_stack = true
}
```

### Template Stacks

Define reusable stack templates:

```hcl
# templates/webapp-stack.hcl

stack {
  name        = var.stack_name
  description = "Full web application stack"
}

unit "vpc" {
  path = "./vpc"
}

unit "alb" {
  path         = "./alb"
  dependencies = ["vpc"]
}

unit "ecs_cluster" {
  path         = "./ecs-cluster"
  dependencies = ["vpc"]
}

unit "ecs_service" {
  path         = "./ecs-service"
  dependencies = ["ecs_cluster", "alb", "rds"]
}

unit "rds" {
  path         = "./rds"
  dependencies = ["vpc"]
}

unit "elasticache" {
  path         = "./elasticache"
  dependencies = ["vpc"]
}
```

Use template by including it:

```hcl
# prod/us-east-1/webapp/terragrunt.stack.hcl

include "template" {
  path = "${get_repo_root()}/templates/webapp-stack.hcl"
}

inputs = {
  stack_name = "prod-webapp"
  environment = "production"
}
```

### Deployment Stacks

Group existing units into deployment stages:

```hcl
# deployment-stacks/phase1-networking.hcl

stack {
  name        = "phase1-networking"
  description = "Phase 1: Core networking infrastructure"
}

unit "prod_us_east_1_vpc" {
  path = "../prod/us-east-1/vpc"
}

unit "prod_eu_west_1_vpc" {
  path = "../prod/eu-west-1/vpc"
}

unit "vpc_peering" {
  path = "../prod/global/vpc-peering"
  dependencies = [
    "prod_us_east_1_vpc",
    "prod_eu_west_1_vpc"
  ]
}
```

```hcl
# deployment-stacks/phase2-compute.hcl

stack {
  name        = "phase2-compute"
  description = "Phase 2: Compute resources (EKS, ECS)"
}

unit "prod_us_east_1_eks" {
  path = "../prod/us-east-1/eks-cluster"
}

unit "prod_us_east_1_ecs" {
  path = "../prod/us-east-1/ecs-cluster"
}
```

---

## State Backend

### S3 + DynamoDB Backend

Best practice for AWS environments:

```hcl
# root.hcl

locals {
  state_bucket_name   = "acme-terraform-state"
  state_bucket_region = "us-east-1"
  dynamodb_table_name = "acme-terraform-locks"
}

remote_state {
  backend = "s3"

  config = {
    bucket         = local.state_bucket_name
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.state_bucket_region
    encrypt        = true
    dynamodb_table = local.dynamodb_table_name

    # Recommended S3 settings
    skip_credentials_validation = true
    skip_metadata_api_check     = true

    # Enable state locking
    dynamodb_table = local.dynamodb_table_name
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
```

### Backend Setup Prerequisites

Create the S3 bucket and DynamoDB table manually or via separate Terraform:

```bash
# Create state bucket
aws s3api create-bucket \
  --bucket acme-terraform-state \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket acme-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket acme-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket acme-terraform-state \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name acme-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Multi-Account Backend Strategy

For organizations with multiple AWS accounts, use separate state buckets per account:

```hcl
# prod/account.hcl
locals {
  account_id = "123456789012"
  state_bucket_name = "acme-terraform-state-prod-${local.account_id}"
}

# staging/account.hcl
locals {
  account_id = "987654321098"
  state_bucket_name = "acme-terraform-state-staging-${local.account_id}"
}
```

---

## Catalog Scaffolding

### Using terragrunt catalog

Create units from catalog templates:

```bash
# Initialize catalog (creates catalog.yaml if not exists)
terragrunt catalog init

# Add a catalog repository
terragrunt catalog repo add acme https://github.com/acme/infrastructure-catalog.git

# List available modules
terragrunt catalog list

# Create a unit from a catalog module
cd prod/us-east-1
terragrunt catalog create acme:vpc:v1.2.0 \
  --dest ./vpc \
  --var vpc_cidr=10.0.0.0/16 \
  --var environment=prod
```

### Catalog Configuration (catalog.yaml)

```yaml
# infrastructure-live/catalog.yaml

repositories:
  - name: acme
    url: https://github.com/acme/infrastructure-catalog.git
    default_ref: main

  - name: community
    url: https://github.com/terraform-aws-modules/terraform-aws-vpc.git
    default_ref: v5.1.0

templates:
  vpc:
    source: acme:modules/vpc
    description: "VPC with public and private subnets"
    default_inputs:
      enable_nat_gateway: true
      enable_dns_hostnames: true

  eks:
    source: acme:modules/eks-cluster
    description: "EKS cluster with managed node groups"
    default_inputs:
      cluster_version: "1.28"
      enable_irsa: true
```

---

## Version Management

### Module Versioning

Use Git tags for module versions:

```bash
# In infrastructure-catalog repository
git tag -a v1.0.0 -m "Initial stable release of VPC module"
git push origin v1.0.0
```

Reference specific versions in units:

```hcl
terraform {
  # Pin to exact version
  source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc?ref=v1.0.0"

  # Or use branch (not recommended for production)
  # source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc?ref=main"
}
```

### Version Constraints

Use version ranges for flexibility:

```hcl
# Accept any 1.x version
source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc?ref=v1"

# Accept any 1.2.x patch version
source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc?ref=v1.2"
```

### Upgrading Versions

Use version control to track module upgrades:

```bash
# Feature branch for upgrade
git checkout -b upgrade-vpc-module

# Edit terragrunt.hcl to bump version
sed -i 's/ref=v1.0.0/ref=v1.1.0/' prod/us-east-1/vpc/terragrunt.hcl

# Plan to see changes
cd prod/us-east-1/vpc
terragrunt plan

# Apply after review
terragrunt apply

# Commit and create PR
git add prod/us-east-1/vpc/terragrunt.hcl
git commit -m "Upgrade VPC module from v1.0.0 to v1.1.0"
git push origin upgrade-vpc-module
```

---

## Performance Optimization

### Provider Caching

Terragrunt can cache provider plugins to speed up initialization:

```bash
# Set environment variable
export TG_PROVIDER_CACHE_DIR="$HOME/.terragrunt/cache/providers"

# Terragrunt will reuse downloaded providers across units
```

Add to shell profile for persistence:

```bash
# ~/.bashrc or ~/.zshrc
export TG_PROVIDER_CACHE_DIR="$HOME/.terragrunt/cache/providers"
```

### Parallelism Configuration

Control concurrent operations:

```bash
# Limit parallel unit execution (default: unlimited)
export TERRAGRUNT_PARALLELISM=10

# Terraform-level parallelism (default: 10)
terragrunt run-all apply --terragrunt-parallelism 5 --terraform-parallelism 5
```

### Download Optimization

Optimize source downloading:

```bash
# Cache Terraform sources
export TERRAGRUNT_SOURCE_CACHE="$HOME/.terragrunt/cache/sources"

# Skip provider download if already cached
export TG_SKIP_PROVIDER_DOWNLOAD=true
```

### Best Practices for Speed

1. **Use provider caching** (saves 5-10s per unit init)
2. **Enable source caching** (saves module download time)
3. **Limit parallelism** on resource-constrained machines
4. **Mock outputs** for fast validation without dependencies
5. **Use stacks** to operate on logical groups efficiently

---

## Common Pitfalls

### 1. Circular Dependencies

**Problem:** Unit A depends on Unit B, which depends on Unit A.

```hcl
# vpc/terragrunt.hcl
dependency "eks" {
  config_path = "../eks-cluster"  # ❌ Circular!
}

# eks-cluster/terragrunt.hcl
dependency "vpc" {
  config_path = "../vpc"  # ❌ Circular!
}
```

**Solution:** Break the cycle by re-architecting dependencies or using data sources instead.

### 2. Missing Mock Outputs

**Problem:** Running `terragrunt plan` fails because dependency hasn't been applied yet.

```hcl
dependency "vpc" {
  config_path = "../vpc"
  # ❌ No mock outputs
}

inputs = {
  vpc_id = dependency.vpc.outputs.vpc_id  # Fails if VPC not applied
}
```

**Solution:** Always provide mock outputs for dependencies:

```hcl
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-mock-12345"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

### 3. Hardcoded Values

**Problem:** Hardcoding values that should come from configuration hierarchy.

```hcl
inputs = {
  aws_region = "us-east-1"  # ❌ Hardcoded
  vpc_cidr   = "10.0.0.0/16"  # ❌ Hardcoded
}
```

**Solution:** Use configuration hierarchy:

```hcl
include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

inputs = {
  aws_region = include.env.locals.aws_region  # ✅ From env.hcl
  vpc_cidr   = include.env.locals.vpc_cidr    # ✅ From env.hcl
}
```

### 4. Incorrect Module References

**Problem:** Wrong path or version in module source.

```hcl
terraform {
  # ❌ Wrong: missing version reference
  source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc"

  # ❌ Wrong: incorrect path
  source = "git::git@github.com:acme/infrastructure-catalog.git//vpc?ref=v1.0.0"
}
```

**Solution:** Use correct format with version:

```hcl
terraform {
  source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc?ref=v1.0.0"
}
```

### 5. State Lock Issues

**Problem:** DynamoDB table not created or misconfigured.

```
Error: Error acquiring the state lock
```

**Solution:** Ensure DynamoDB table exists with correct schema (LockID as partition key).

### 6. Dependency Output Mismatch

**Problem:** Referencing an output that doesn't exist in the dependency.

```hcl
dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  vpc_id = dependency.vpc.outputs.id  # ❌ Output is named "vpc_id", not "id"
}
```

**Solution:** Check the dependency's outputs and use correct names:

```bash
# Check available outputs
cd ../vpc
terragrunt output

# Use correct output name
inputs = {
  vpc_id = dependency.vpc.outputs.vpc_id  # ✅ Correct
}
```

### 7. Provider Configuration Conflicts

**Problem:** Multiple provider configurations for the same provider.

```hcl
# Generated by root.hcl
provider "aws" {
  region = var.aws_region
}

# Also in main.tf (conflict!)
provider "aws" {
  region = "us-east-1"
}
```

**Solution:** Use only generated providers from Terragrunt. Remove provider blocks from Terraform modules.

### 8. Path Resolution Issues

**Problem:** Incorrect relative paths in dependencies.

```hcl
dependency "vpc" {
  config_path = "./vpc"  # ❌ Wrong if not in same directory
}
```

**Solution:** Use correct relative paths from current unit:

```hcl
dependency "vpc" {
  config_path = "../vpc"  # ✅ Up one directory, then into vpc
}
```

### 9. Forgetting to Include Parent Configs

**Problem:** Not including parent configuration files.

```hcl
# ❌ Missing root.hcl include
terraform {
  source = "..."
}

inputs = {
  # Won't have access to root configuration
}
```

**Solution:** Always include necessary parent configs:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}
```

### 10. Mixing Configuration Patterns

**Problem:** Inconsistent use of locals, inputs, and variables.

```hcl
# Confusing mix
locals {
  region = "us-east-1"
}

inputs = {
  aws_region = var.region  # ❌ Using var instead of local
}
```

**Solution:** Follow consistent patterns (prefer configuration hierarchy over locals).

---

## Summary

**Key Takeaways:**

1. **Separation of concerns**: Catalog (modules) vs Live (instantiations)
2. **Configuration hierarchy**: root.hcl → account.hcl → env.hcl → terragrunt.hcl
3. **Dependencies**: Use dependency blocks with mock outputs
4. **Stacks**: Group units for coordinated operations
5. **State management**: S3 + DynamoDB for AWS, with proper locking
6. **Versioning**: Use Git tags for module versions
7. **Performance**: Enable provider and source caching
8. **Avoid pitfalls**: Mock outputs, correct paths, configuration hierarchy

**Next Steps:**

- Review [terragrunt-commands.md](./terragrunt-commands.md) for operational commands
- Study example repositories for real-world patterns
- Start with simple units and gradually add complexity
