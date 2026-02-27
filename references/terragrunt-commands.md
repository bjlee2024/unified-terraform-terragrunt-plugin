# Terragrunt Commands Reference

Comprehensive guide to Terragrunt CLI commands, targeting, filtering, and operational workflows.

## Table of Contents

- [Stack Commands](#stack-commands)
- [Targeting Specific Units](#targeting-specific-units)
- [Filter Expressions](#filter-expressions)
- [Advanced Filtering](#advanced-filtering)
- [Parallelism Control](#parallelism-control)
- [DAG Visualization](#dag-visualization)
- [Common Operations](#common-operations)
- [Best Practices](#best-practices)
- [Environment Variables](#environment-variables)

---

## Stack Commands

### Generate Stack

Create Terraform files from stack configuration:

```bash
# Generate all units in stack
terragrunt stack generate

# Generate specific unit
terragrunt stack generate --unit vpc
```

### Stack Plan

Preview changes for all units in the stack:

```bash
# Plan all units
terragrunt stack run plan

# Plan with parallelism
terragrunt stack run plan --terragrunt-parallelism 5

# Plan specific units only
terragrunt stack run plan --queue-include-dir vpc --queue-include-dir eks-cluster

# Plan and save output
terragrunt stack run plan > stack-plan.txt
```

### Stack Apply

Apply changes to all units in the stack:

```bash
# Apply all units
terragrunt stack run apply

# Apply with auto-approve (dangerous!)
terragrunt stack run apply --terragrunt-non-interactive

# Apply specific units
terragrunt stack run apply --queue-include-dir vpc

# Apply with limited parallelism
terragrunt stack run apply --terragrunt-parallelism 3
```

### Stack Destroy

Destroy infrastructure in reverse dependency order:

```bash
# Destroy all units (prompts for confirmation)
terragrunt stack run destroy

# Destroy with auto-approve (very dangerous!)
terragrunt stack run destroy --terragrunt-non-interactive

# Destroy specific units
terragrunt stack run destroy --queue-include-dir old-service

# Dry-run destroy (shows what would be destroyed)
terragrunt stack run plan -destroy
```

### Stack Output

Get outputs from all units:

```bash
# Show all outputs
terragrunt stack output

# Show outputs in JSON format
terragrunt stack output --json

# Show output from specific unit
terragrunt stack output --unit vpc
```

### Stack Clean

Clean up generated files:

```bash
# Clean all generated Terraform files
terragrunt stack clean

# Clean specific unit
terragrunt stack clean --unit vpc

# Clean and remove cached modules
terragrunt stack clean --terragrunt-source-delete
```

---

## Targeting Specific Units

### By Directory (--queue-include-dir)

Include specific units by their directory path:

```bash
# Include single unit
terragrunt stack run plan --queue-include-dir vpc

# Include multiple units
terragrunt stack run plan \
  --queue-include-dir vpc \
  --queue-include-dir eks-cluster \
  --queue-include-dir rds-primary

# Include units with relative paths
cd prod/us-east-1
terragrunt stack run plan --queue-include-dir ./vpc --queue-include-dir ./eks-cluster
```

### By Pattern (--queue-include-pattern)

Include units matching a glob pattern:

```bash
# Include all VPC units
terragrunt stack run plan --queue-include-pattern "**/vpc"

# Include all database units
terragrunt stack run plan --queue-include-pattern "**/*db*"

# Include all units in specific region
terragrunt stack run plan --queue-include-pattern "prod/us-east-1/**"
```

### Exclude Units (--queue-exclude-dir)

Exclude specific units from operation:

```bash
# Exclude single unit
terragrunt stack run plan --queue-exclude-dir legacy-service

# Exclude multiple units
terragrunt stack run apply \
  --queue-exclude-dir test-unit \
  --queue-exclude-dir deprecated-service

# Exclude by pattern
terragrunt stack run plan --queue-exclude-pattern "**/*-test"
```

### Using Filters (--filter)

Advanced filtering with boolean expressions:

```bash
# Include units with specific tag
terragrunt stack run plan --filter 'attr.tags.Tier == "networking"'

# Exclude units by name pattern
terragrunt stack run plan --filter 'name != "test-*"'

# Complex filter combining conditions
terragrunt stack run apply --filter 'attr.tags.Environment == "prod" && path.contains("us-east-1")'
```

---

## Filter Expressions

Filter expressions provide powerful querying capabilities for selecting units.

### Available Filter Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | string | Unit name | `name == "vpc"` |
| `path` | string | Unit directory path | `path.contains("us-east-1")` |
| `attr.*` | any | Unit attributes from terragrunt.hcl | `attr.tags.Tier == "compute"` |
| `dependencies` | list | List of dependency names | `"vpc" in dependencies` |
| `dependents` | list | List of units that depend on this unit | `len(dependents) > 0` |

### String Operations

```bash
# Exact match
--filter 'name == "vpc"'

# Not equal
--filter 'name != "test-unit"'

# Contains substring
--filter 'path.contains("prod")'

# Starts with
--filter 'name.startsWith("eks")'

# Ends with
--filter 'name.endsWith("-primary")'

# Regex match
--filter 'name.matches("^vpc-.*")'
```

### Numeric Operations

```bash
# Greater than
--filter 'attr.instance_count > 5'

# Less than or equal
--filter 'attr.priority <= 10'

# Range
--filter 'attr.port >= 1000 && attr.port <= 9999'
```

### List Operations

```bash
# Check if item in list
--filter '"vpc" in dependencies'

# Check list length
--filter 'len(dependencies) > 2'

# Empty list check
--filter 'len(dependents) == 0'
```

### Boolean Operations

```bash
# AND
--filter 'attr.enabled == true && name == "vpc"'

# OR
--filter 'path.contains("prod") || path.contains("staging")'

# NOT
--filter '!(name.contains("test"))'

# Complex
--filter '(attr.environment == "prod" || attr.environment == "staging") && attr.critical == true'
```

### Attribute Access

Access nested attributes:

```bash
# Top-level attribute
--filter 'attr.environment == "prod"'

# Nested attribute
--filter 'attr.tags.Tier == "networking"'

# Map access
--filter 'attr.config.region == "us-east-1"'

# Array access (0-indexed)
--filter 'attr.availability_zones[0] == "us-east-1a"'
```

---

## Advanced Filtering

### Dependency-Based Filtering

Select units based on their dependencies:

```bash
# Units that depend on VPC
terragrunt stack run plan --filter '"vpc" in dependencies'

# Units with more than 2 dependencies
terragrunt stack run plan --filter 'len(dependencies) > 2'

# Units with no dependencies (leaf nodes)
terragrunt stack run plan --filter 'len(dependencies) == 0'

# Units that are dependencies of others
terragrunt stack run plan --filter 'len(dependents) > 0'

# Units that nothing depends on (can be safely removed)
terragrunt stack run plan --filter 'len(dependents) == 0'
```

### Tag-Based Filtering

Filter by tags defined in unit inputs:

```bash
# Production environment units
terragrunt stack run plan --filter 'attr.tags.Environment == "prod"'

# Networking tier units
terragrunt stack run plan --filter 'attr.tags.Tier == "networking"'

# Critical infrastructure
terragrunt stack run plan --filter 'attr.tags.Critical == "true"'

# Multiple tag conditions
terragrunt stack run plan --filter 'attr.tags.Environment == "prod" && attr.tags.Tier == "compute"'
```

### Path-Based Filtering

Filter by directory structure:

```bash
# All units in production
terragrunt stack run plan --filter 'path.contains("prod/")'

# All units in us-east-1
terragrunt stack run plan --filter 'path.contains("us-east-1")'

# All units in specific account and region
terragrunt stack run plan --filter 'path.contains("prod/us-east-1")'

# Exclude test/dev environments
terragrunt stack run plan --filter '!path.contains("test") && !path.contains("dev")'
```

### Git-Based Filtering

Filter units by Git changes (requires git integration):

```bash
# Units with uncommitted changes
terragrunt stack run plan --filter 'git.changed == true'

# Units changed in last commit
terragrunt stack run plan --filter 'git.changed_in_commit("HEAD")'

# Units changed in feature branch
terragrunt stack run plan --filter 'git.changed_since("origin/main")'
```

### Combined Filters

Combine multiple filtering criteria:

```bash
# Production networking units in us-east-1
terragrunt stack run plan --filter '
  attr.tags.Environment == "prod" &&
  attr.tags.Tier == "networking" &&
  path.contains("us-east-1")
'

# Non-test units that depend on VPC
terragrunt stack run plan --filter '
  "vpc" in dependencies &&
  !name.contains("test")
'

# Critical units with multiple dependencies
terragrunt stack run plan --filter '
  attr.tags.Critical == "true" &&
  len(dependencies) >= 2
'
```

---

## Parallelism Control

### Terragrunt Parallelism

Controls how many units are processed concurrently:

```bash
# Default (unlimited)
terragrunt stack run apply

# Limit to 5 units at a time
terragrunt stack run apply --terragrunt-parallelism 5

# Sequential execution (one at a time)
terragrunt stack run apply --terragrunt-parallelism 1

# High parallelism for fast operations
terragrunt stack run plan --terragrunt-parallelism 20
```

### Terraform Parallelism

Controls concurrent Terraform resource operations within a unit:

```bash
# Default Terraform parallelism (10)
terragrunt apply

# Reduce for API rate limits
terragrunt apply --terraform-parallelism 3

# Increase for faster applies
terragrunt apply --terraform-parallelism 20

# Combined with stack operations
terragrunt stack run apply \
  --terragrunt-parallelism 5 \
  --terraform-parallelism 5
```

### Performance Tuning

Balance between speed and resource usage:

```bash
# Conservative (low resource usage)
terragrunt stack run apply \
  --terragrunt-parallelism 3 \
  --terraform-parallelism 5

# Moderate (balanced)
terragrunt stack run apply \
  --terragrunt-parallelism 5 \
  --terraform-parallelism 10

# Aggressive (fast but resource-intensive)
terragrunt stack run apply \
  --terragrunt-parallelism 10 \
  --terraform-parallelism 20

# Maximum (use with caution)
terragrunt stack run apply \
  --terragrunt-parallelism 0 \
  --terraform-parallelism 50
```

**Note:** `--terragrunt-parallelism 0` means unlimited parallelism.

---

## DAG Visualization

### View Dependency Graph

Visualize unit dependencies:

```bash
# Show dependency graph
terragrunt graph

# Output as DOT format
terragrunt graph > dependencies.dot

# Generate PNG image (requires graphviz)
terragrunt graph | dot -Tpng > dependencies.png

# Generate SVG (interactive, zoomable)
terragrunt graph | dot -Tsvg > dependencies.svg
```

### Graph from Stack

Visualize specific stack dependencies:

```bash
# Graph for entire stack
terragrunt stack graph

# Graph for specific units
terragrunt stack graph --queue-include-dir vpc --queue-include-dir eks-cluster

# Filter graph
terragrunt stack graph --filter 'attr.tags.Environment == "prod"'
```

### Interpreting the Graph

```
┌─────────┐
│   VPC   │
└────┬────┘
     │
     ├──────────────┬────────────┐
     │              │            │
┌────▼─────┐  ┌────▼────┐  ┌───▼─────┐
│   EKS    │  │   RDS   │  │  Redis  │
└──────────┘  └────┬────┘  └─────────┘
                   │
              ┌────▼─────────┐
              │  RDS Replica │
              └──────────────┘
```

- **Nodes**: Individual infrastructure units
- **Edges**: Dependencies (arrows point from dependent to dependency)
- **Execution order**: Bottom-up (dependencies first)
- **Parallelization**: Units at same level can run in parallel

---

## Common Operations

### Create New Unit

```bash
# Navigate to environment directory
cd prod/us-east-1

# Create unit directory
mkdir rds-postgres

# Create terragrunt.hcl
cat > rds-postgres/terragrunt.hcl <<EOF
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

terraform {
  source = "git::git@github.com:acme/infrastructure-catalog.git//modules/rds-postgres?ref=v1.0.0"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-mock"
    private_subnet_ids = ["subnet-mock-1", "subnet-mock-2"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  identifier = "prod-main-db"
  engine_version = "15.4"
  instance_class = "db.r6g.large"

  vpc_id = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnet_ids

  backup_retention_period = 30
  multi_az = true
}
EOF

# Initialize and validate
cd rds-postgres
terragrunt init
terragrunt validate

# Plan to see what will be created
terragrunt plan
```

### Create Stack Configuration

```bash
# Navigate to environment directory
cd prod/us-east-1

# Create stack file
cat > terragrunt.stack.hcl <<EOF
stack {
  name = "prod-us-east-1-core"
  description = "Core production infrastructure in US-East-1"
}

unit "vpc" {
  path = "./vpc"
}

unit "eks_cluster" {
  path = "./eks-cluster"
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
EOF

# Generate stack
terragrunt stack generate

# Plan entire stack
terragrunt stack run plan
```

### Deploy to New Environment

```bash
# Copy existing environment structure
cp -r prod/us-east-1 prod/eu-west-1

# Update env.hcl for new region
cat > prod/eu-west-1/env.hcl <<EOF
locals {
  aws_region = "eu-west-1"
  region_short = "euw1"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  vpc_cidr = "10.1.0.0/16"
}

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
    aws_region = local.aws_region
    availability_zones = local.availability_zones
    vpc_cidr = local.vpc_cidr
  }
)
EOF

# Update unit configurations as needed
# Then deploy
cd prod/eu-west-1
terragrunt stack run apply
```

### Update Module Version

```bash
# Find all units using specific module
grep -r "modules/vpc?ref=v1.0.0" prod/

# Update to new version
find prod/ -name "terragrunt.hcl" -exec sed -i '' 's/ref=v1.0.0/ref=v1.1.0/g' {} \;

# Review changes
git diff

# Plan to see infrastructure changes
cd prod/us-east-1/vpc
terragrunt plan

# Apply if changes look good
terragrunt apply

# Commit the module version update
git add .
git commit -m "Upgrade VPC module from v1.0.0 to v1.1.0"
```

### Migrate State

Move state from one backend to another:

```bash
# Backup current state
terragrunt state pull > backup.tfstate

# Update backend configuration in root.hcl
# (change bucket name, region, etc.)

# Re-initialize with new backend
terragrunt init -migrate-state

# Verify state migrated correctly
terragrunt state list
```

### Import Existing Resource

```bash
# Navigate to unit
cd prod/us-east-1/vpc

# Import resource into state
terragrunt import aws_vpc.main vpc-abc123

# Plan to verify
terragrunt plan

# If plan shows no changes, import was successful
```

### Clean Up Orphaned Resources

```bash
# List resources in state
terragrunt state list

# Remove orphaned resource from state
terragrunt state rm aws_instance.old_server

# Or destroy and remove unit entirely
terragrunt destroy
cd ..
rm -rf old-unit/
```

---

## Best Practices

### 1. Always Use Version Pinning

```bash
# ✅ Good: Pinned version
terraform {
  source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc?ref=v1.2.0"
}

# ❌ Bad: No version (uses latest)
terraform {
  source = "git::git@github.com:acme/infrastructure-catalog.git//modules/vpc"
}
```

### 2. Plan Before Apply

```bash
# Always review plan output
terragrunt plan > plan.txt
less plan.txt

# For stacks, save plan for each unit
terragrunt stack run plan 2>&1 | tee stack-plan.txt
```

### 3. Use Mock Outputs

```bash
# Always provide mock outputs for dependencies
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-mock-12345"
    subnet_ids = ["subnet-mock-1", "subnet-mock-2"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

### 4. Control Parallelism

```bash
# Start conservative, increase gradually
terragrunt stack run apply --terragrunt-parallelism 3

# Monitor resource usage and adjust
# (CPU, memory, API rate limits)
```

### 5. Use Filters for Large Stacks

```bash
# Don't apply everything at once
# Use filters to work on logical groups

# First: networking
terragrunt stack run apply --filter 'attr.tags.Tier == "networking"'

# Then: compute
terragrunt stack run apply --filter 'attr.tags.Tier == "compute"'

# Finally: data
terragrunt stack run apply --filter 'attr.tags.Tier == "data"'
```

### 6. Validate Before Committing

```bash
# Validate all units
terragrunt stack run validate

# Format Terraform files
terragrunt fmt -recursive

# Run static analysis (if available)
tflint --recursive
```

### 7. Document Dependencies

```bash
# Generate and commit dependency graph
terragrunt graph | dot -Tsvg > docs/dependencies.svg
git add docs/dependencies.svg
git commit -m "Update dependency graph"
```

### 8. Test in Non-Production First

```bash
# Always test changes in dev/staging first
cd dev/us-west-2
terragrunt stack run apply

# Verify everything works
# Then apply to production
cd ../../prod/us-east-1
terragrunt stack run apply
```

### 9. Use Git for Change Management

```bash
# Create feature branch
git checkout -b feature/add-redis-cache

# Make changes
# ...

# Commit and push
git add .
git commit -m "Add Redis cache unit to production stack"
git push origin feature/add-redis-cache

# Create PR for review
gh pr create --title "Add Redis cache" --body "Adds Redis cache unit for session storage"
```

### 10. Monitor Apply Progress

```bash
# Use verbose output to monitor progress
terragrunt stack run apply --terragrunt-log-level debug

# Or use separate terminal to watch logs
tail -f /var/log/terragrunt.log

# Monitor AWS CloudTrail for API calls
# Monitor resource creation in AWS Console
```

---

## Environment Variables

### Essential Variables

```bash
# Provider caching (saves time)
export TG_PROVIDER_CACHE_DIR="$HOME/.terragrunt/cache/providers"

# Source caching (saves downloads)
export TERRAGRUNT_SOURCE_CACHE="$HOME/.terragrunt/cache/sources"

# Parallelism control
export TERRAGRUNT_PARALLELISM=5

# Non-interactive mode (CI/CD)
export TERRAGRUNT_NON_INTERACTIVE=true

# Log level
export TERRAGRUNT_LOG_LEVEL=info  # debug, info, warn, error
```

### AWS-Specific Variables

```bash
# AWS credentials
export AWS_PROFILE=production
export AWS_REGION=us-east-1

# Or use explicit credentials
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key

# Session token (if using MFA)
export AWS_SESSION_TOKEN=your_session_token
```

### Performance Variables

```bash
# Skip provider installation if cached
export TG_SKIP_PROVIDER_DOWNLOAD=false

# Disable provider plugin checksum verification (faster, less secure)
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true

# Increase HTTP timeout for slow connections
export TG_HTTP_TIMEOUT=300

# Parallel downloads
export TG_PARALLELISM=10
```

### CI/CD Variables

```bash
# Disable color output (better for logs)
export TF_CLI_ARGS=-no-color
export TERRAGRUNT_NO_COLOR=true

# Auto-approve (dangerous, use with caution)
export TF_INPUT=false
export TERRAGRUNT_NON_INTERACTIVE=true

# Lock timeout for concurrent runs
export TF_LOCK_TIMEOUT=10m
```

### Debug Variables

```bash
# Enable debug logging
export TF_LOG=DEBUG
export TERRAGRUNT_LOG_LEVEL=debug

# Log to file
export TF_LOG_PATH=/tmp/terraform.log

# Show detailed crash logs
export TF_CRASH_LOG_PATH=/tmp/terraform-crash.log
```

### Recommended Shell Configuration

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Terragrunt performance optimization
export TG_PROVIDER_CACHE_DIR="$HOME/.terragrunt/cache/providers"
export TERRAGRUNT_SOURCE_CACHE="$HOME/.terragrunt/cache/sources"
export TERRAGRUNT_PARALLELISM=5

# AWS configuration
export AWS_REGION=us-east-1
export AWS_PAGER=""  # Disable paging for AWS CLI

# Terraform configuration
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

# Create cache directories
mkdir -p "$TG_PROVIDER_CACHE_DIR"
mkdir -p "$TERRAGRUNT_SOURCE_CACHE"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

# Helpful aliases
alias tg='terragrunt'
alias tgp='terragrunt plan'
alias tga='terragrunt apply'
alias tgd='terragrunt destroy'
alias tgs='terragrunt stack'
alias tgsp='terragrunt stack run plan'
alias tgsa='terragrunt stack run apply'
```

---

## Summary

**Core Commands:**
- `terragrunt stack run [command]` - Execute Terraform command across stack
- `terragrunt stack generate` - Generate Terraform files
- `terragrunt stack output` - Show outputs from all units
- `terragrunt graph` - Visualize dependencies

**Targeting:**
- `--queue-include-dir` - Include specific units
- `--queue-exclude-dir` - Exclude specific units
- `--filter` - Advanced filtering with expressions

**Control:**
- `--terragrunt-parallelism` - Concurrent units
- `--terraform-parallelism` - Concurrent resources within a unit
- `--terragrunt-non-interactive` - Auto-approve (CI/CD)

**Best Practices:**
- Always use version pinning for modules
- Provide mock outputs for dependencies
- Plan before applying
- Use filters for large-scale operations
- Control parallelism based on resources
- Test in non-production first
- Use Git for change management

**Performance:**
- Enable provider and source caching
- Use appropriate parallelism settings
- Filter to work on logical groups
- Monitor resource usage and API limits
