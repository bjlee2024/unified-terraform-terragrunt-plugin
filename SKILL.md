---
name: unified-terraform-terragrunt
description: Unified Terraform, Terragrunt, and HCP Stacks best practices with modern features (1.1-1.11+)
license: Apache-2.0
---

# Unified Terraform, Terragrunt, and HCP Stacks Skill

**Version:** 1.0.0
**Last Updated:** 2026-02-05

---

## Table of Contents

1. [When to Use This Skill](#when-to-use-this-skill)
2. [Tool Selection Decision Matrix](#tool-selection-decision-matrix)
3. [Testing Strategy Pyramid](#testing-strategy-pyramid)
4. [Modern Terraform Features Quick Reference](#modern-terraform-features-quick-reference)
5. [Conflict Resolutions Applied](#conflict-resolutions-applied)
6. [Reference Files Navigation](#reference-files-navigation)
7. [Common Anti-Patterns](#common-anti-patterns)
8. [Quick Start Examples](#quick-start-examples)
9. [License](#license)

---

## When to Use This Skill

This skill is automatically activated when you detect:

### Primary Triggers
- User mentions: `terraform`, `terragrunt`, `opentofu`, `tofu`, `hcl`, `infrastructure as code`, `iac`, `stacks`
- File extensions: `.tf`, `.hcl`, `.tfvars`, `.tftest.hcl`
- Configuration files: `terragrunt.hcl`, `terraform.tfvars`, `versions.tf`
- Commands: `terraform apply`, `terragrunt run-all`, `tofu plan`

### Use Cases
- Writing or reviewing Terraform/OpenTofu configurations
- Designing module hierarchies and interfaces
- Implementing Terragrunt catalog/live architecture
- Configuring HCP Terraform Stacks orchestration
- Setting up CI/CD pipelines for infrastructure
- Testing infrastructure code (unit, integration, E2E)
- Managing state backends and migrations
- Security scanning and compliance validation

### When NOT to Use
- Pure Ansible/Puppet/Chef configuration management (unless hybrid)
- CloudFormation without Terraform interop
- Kubernetes manifests without Terraform provider
- Application code (unless infrastructure provisioning logic)

---

## Tool Selection Decision Matrix

Choose the right tool for your infrastructure scale and complexity:

| Scenario | Recommended Tool | Rationale |
|----------|------------------|-----------|
| **Single project, 1-2 environments** | Terraform/OpenTofu | Simple, direct, minimal overhead |
| **Multi-environment (dev/stage/prod)** | Terragrunt | DRY configuration, environment-specific overrides |
| **Multi-region, multi-account AWS** | Terragrunt | Account/region hierarchy, role assumption |
| **Multi-cloud with shared modules** | Terragrunt | Cross-cloud module reuse, consistent patterns |
| **10+ stacks with dependencies** | HCP Terraform Stacks | Orchestration graph, parallel execution |
| **Compliance-heavy (SOC2/HIPAA)** | Terragrunt + Stacks | Policy-as-code, approval workflows |
| **Mono-repo with many teams** | Terragrunt | Isolated state per team, shared catalog |
| **GitOps with Atlantis/Spacelift** | Terragrunt | Native integration, plan/apply automation |

### Decision Flowchart

```
Start
  │
  ├─ Single environment? ──Yes──> Terraform/OpenTofu
  │
  ├─ 2-5 environments? ───Yes──> Terragrunt (catalog/live)
  │
  ├─ 5+ stacks with dependencies? ──Yes──> HCP Terraform Stacks
  │
  └─ Multi-cloud + compliance? ──Yes──> Terragrunt + Stacks hybrid
```

### Migration Paths

| From | To | When |
|------|-----|------|
| Terraform → Terragrunt | Growing beyond 3 environments, DRY violations | Copy modules to catalog, create live hierarchy |
| Terragrunt → Stacks | 10+ stacks, orchestration bottlenecks | Convert to `.tfstack.hcl`, define components |
| CloudFormation → Terraform | Cross-cloud support needed | Use `aws_cloudformation_stack` data source |
| Pulumi → Terraform | Team prefers HCL, existing TF modules | Export state, recreate resources |

---

## Testing Strategy Pyramid

Apply a **layered testing approach** to catch issues early:

```
                    ┌─────────────┐
                    │   E2E Tests │  ← Full deployment, real cloud
                    └─────────────┘
                  ┌───────────────────┐
                  │ Integration Tests │  ← Real providers, isolated envs
                  └───────────────────┘
              ┌─────────────────────────────┐
              │       Unit Tests            │  ← Mock providers, .tftest.hcl
              └─────────────────────────────┘
          ┌───────────────────────────────────────┐
          │       Static Analysis                 │  ← tflint, checkov, trivy
          └───────────────────────────────────────┘
```

### Testing Tiers

| Tier | Tools | Speed | Coverage | Cost |
|------|-------|-------|----------|------|
| **Static Analysis** | tflint, checkov, trivy, tfsec | <1s | Syntax, security, best practices | Free |
| **Unit Tests** | `.tftest.hcl` with mocks | <5s | Logic, conditionals, transformations | Free |
| **Integration Tests** | `.tftest.hcl` with real providers | 30-60s | Provider interactions, API calls | $ Low |
| **E2E Tests** | Terratest, Kitchen-Terraform | 5-15min | Full stack, dependencies | $$$ High |

### Recommended Workflow

1. **Pre-commit**: `tflint`, `terraform fmt`, `terraform validate`
2. **PR/MR**: Unit tests (`.tftest.hcl` with mocks), `checkov` scan
3. **Post-merge**: Integration tests (isolated test account)
4. **Release**: E2E tests (staging environment)

---

## Modern Terraform Features Quick Reference

Stay current with Terraform 1.1+ enhancements:

| Version | Feature | Use Case | Reference |
|---------|---------|----------|-----------|
| **1.1+** | `moved` blocks | Refactor without destroying resources | [terraform-patterns.md](references/terraform-patterns.md#moved-blocks) |
| **1.2+** | Preconditions/Postconditions | Input validation, output assertions | [terraform-patterns.md](references/terraform-patterns.md#conditions) |
| **1.3+** | Optional object attributes | Flexible variable schemas | [terraform-modules.md](references/terraform-modules.md#optional-attributes) |
| **1.4+** | `terraform test` command | Native test runner | [terraform-testing.md](references/terraform-testing.md#native-testing) |
| **1.5+** | `check` blocks | Runtime validation without failing | [terraform-patterns.md](references/terraform-patterns.md#check-blocks) |
| **1.5+** | `import` blocks | Declarative resource imports | [state-management.md](references/state-management.md#import-blocks) |
| **1.6+** | `.tftest.hcl` files | Declarative test suites | [terraform-testing.md](references/terraform-testing.md#tftest-syntax) |
| **1.7+** | `removed` blocks | Graceful resource removal | [terraform-patterns.md](references/terraform-patterns.md#removed-blocks) |
| **1.9+** | Input validation improvements | Better error messages | [terraform-modules.md](references/terraform-modules.md#input-validation) |
| **1.10+** | Ephemeral resources | Temporary resources (test DBs) | [terraform-patterns.md](references/terraform-patterns.md#ephemeral) |
| **1.11+** | Write-only arguments | Sensitive data protection | [security-compliance.md](references/security-compliance.md#write-only) |

### Adoption Priority

**High Priority** (adopt immediately):
- `moved` blocks (safe refactoring)
- Optional object attributes (flexible APIs)
- `.tftest.hcl` files (structured testing)
- `import` blocks (declarative imports)

**Medium Priority** (adopt for new projects):
- `check` blocks (non-blocking validation)
- Write-only arguments (secrets management)
- Ephemeral resources (testing)

**Low Priority** (niche use cases):
- `removed` blocks (gradual deprecation)

---

## Conflict Resolutions Applied

This skill consolidates conflicting guidance from multiple sources. Below are the **7 key decisions** made:

### 1. File Naming: `versions.tf` vs `terraform.tf`

**Decision:** Use `versions.tf`

**Rationale:**
- Official HashiCorp docs use `versions.tf`
- Community convention (Terraform Registry examples)
- Semantic clarity: file contains version constraints

**Pattern:**
```hcl
# versions.tf
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### 2. Secrets Management: Write-Only vs External

**Decision:** Use write-only arguments (1.11+) for Terraform-managed secrets, external secret managers for application secrets

**Pattern:**
```hcl
# Terraform-managed secret (RDS password)
resource "aws_db_instance" "main" {
  password = var.db_password  # write-only in 1.11+
}

# Application secret (API key)
resource "aws_secretsmanager_secret" "api_key" {
  name = "app/api-key"
  # Value injected via CI/CD, not stored in Terraform
}
```

**Reference:** [security-compliance.md](references/security-compliance.md#secrets-management)

### 3. Resource Iteration: `count` vs `for_each`

**Decision:** Prefer `for_each` with maps/sets for stable resource addressing

**Rationale:**
- `count` uses numeric indices (fragile with reordering)
- `for_each` uses keys (stable across changes)

**Pattern:**
```hcl
# DO: Stable addressing
resource "aws_instance" "web" {
  for_each = toset(["web-1", "web-2", "web-3"])

  tags = {
    Name = each.key
  }
}

# DON'T: Fragile numeric indices
resource "aws_instance" "web" {
  count = 3

  tags = {
    Name = "web-${count.index}"
  }
}
```

**Reference:** [terraform-patterns.md](references/terraform-patterns.md#iteration)

### 4. Singleton Naming: `this` Convention

**Decision:** Reserve `this` for TRUE singletons only (one resource type per module)

**Pattern:**
```hcl
# DO: Singleton VPC module
resource "aws_vpc" "this" {
  cidr_block = var.cidr_block
}

# DON'T: Multiple resource types with "this"
resource "aws_vpc" "this" {}
resource "aws_subnet" "this" {}  # Ambiguous!

# DO: Use descriptive names for multiple resources
resource "aws_vpc" "main" {}
resource "aws_subnet" "public" {}
resource "aws_subnet" "private" {}
```

**Reference:** [terraform-modules.md](references/terraform-modules.md#naming-conventions)

### 5. Testing: Mocks vs Real Providers

**Decision:** Mocks for unit tests, real providers for integration tests

**Pattern:**
```hcl
# tests/unit.tftest.hcl (mocks)
mock_provider "aws" {
  mock_resource "aws_instance" {
    defaults = {
      id = "i-12345"
    }
  }
}

# tests/integration.tftest.hcl (real providers)
run "create_vpc" {
  command = apply

  assert {
    condition     = aws_vpc.main.id != ""
    error_message = "VPC must be created"
  }
}
```

**Reference:** [terraform-testing.md](references/terraform-testing.md#mocks-vs-real)

### 6. State Backend: Hardcoded vs Dynamic

**Decision:** Use dynamic backend selection with environment-specific configuration

**Pattern:**
```hcl
# backend.tf (template)
terraform {
  backend "s3" {
    # Configured via -backend-config or TF_VAR_* at runtime
  }
}

# environments/dev.s3.tfbackend
bucket         = "myapp-tfstate-dev"
key            = "vpc/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "terraform-locks"
encrypt        = true
```

**Usage:**
```bash
terraform init -backend-config=environments/dev.s3.tfbackend
```

**Reference:** [state-management.md](references/state-management.md#dynamic-backends)

### 7. Module Versioning: Exact vs Loose

**Decision:** Use `~> X.Y` constraints (minor version range)

**Rationale:**
- `~> 1.2` allows 1.2.x patches (bug fixes)
- Prevents breaking changes from 2.0
- Balances stability and security updates

**Pattern:**
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"  # Allows 5.0.x, 5.1.x, not 6.0
}
```

**Reference:** [terraform-modules.md](references/terraform-modules.md#versioning)

---

## Reference Files Navigation

Dive deeper into specific topics with these reference files:

### Core Terraform

| File | Topics Covered | When to Read |
|------|----------------|--------------|
| **[terraform-patterns.md](references/terraform-patterns.md)** | Block ordering, modern features (1.1-1.11+), anti-patterns | Writing new Terraform code |
| **[terraform-modules.md](references/terraform-modules.md)** | Module hierarchy, interface design, refactoring | Designing reusable modules |
| **[terraform-testing.md](references/terraform-testing.md)** | `.tftest.hcl` syntax, mocks, assertions, test organization | Writing test suites |
| **[state-management.md](references/state-management.md)** | Backends, locking, remote state, migrations, import/removed blocks | Managing stateful infrastructure |

### Terragrunt

| File | Topics Covered | When to Read |
|------|----------------|--------------|
| **[terragrunt-patterns.md](references/terragrunt-patterns.md)** | Catalog/live architecture, DRY patterns, dependency management | Structuring multi-environment setups |
| **[terragrunt-commands.md](references/terragrunt-commands.md)** | Stack commands, filter expressions, run-all vs run-in-order | Executing Terragrunt workflows |

### HCP Terraform Stacks

| File | Topics Covered | When to Read |
|------|----------------|--------------|
| **[terraform-stacks.md](references/terraform-stacks.md)** | `.tfstack.hcl` syntax, components, orchestration, deployments | Configuring HCP Stacks orchestration |

### CI/CD & Security

| File | Topics Covered | When to Read |
|------|----------------|--------------|
| **[ci-cd-pipelines.md](references/ci-cd-pipelines.md)** | GitHub Actions, GitLab CI, OIDC, approval workflows | Setting up automation pipelines |
| **[security-compliance.md](references/security-compliance.md)** | Secrets management, encryption, scanning (checkov/trivy), policies | Hardening infrastructure security |

### Quick Lookup

| File | Topics Covered | When to Read |
|------|----------------|--------------|
| **[quick-reference.md](references/quick-reference.md)** | Command cheat sheets, common patterns, troubleshooting | Quick lookups during development |

---

## Common Anti-Patterns

Avoid these frequent mistakes:

### 1. Hardcoded Values

```hcl
# DON'T
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"  # Hardcoded AMI
  instance_type = "t2.micro"

  tags = {
    Environment = "production"  # Hardcoded environment
  }
}

# DO
variable "ami_id" {
  description = "AMI ID for web servers"
  type        = string
}

resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type

  tags = merge(var.common_tags, {
    Environment = var.environment
  })
}
```

### 2. Inline Modules Without Versioning

```hcl
# DON'T
module "vpc" {
  source = "github.com/myorg/terraform-modules//vpc"  # No version!
}

# DO
module "vpc" {
  source  = "github.com/myorg/terraform-modules//vpc?ref=v1.2.0"
  # OR use Terraform Registry
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
}
```

### 3. Mixing Concerns in Root Modules

```hcl
# DON'T: 1500 lines mixing VPC, EKS, RDS, IAM
resource "aws_vpc" "main" { }
resource "aws_eks_cluster" "main" { }
resource "aws_db_instance" "main" { }
resource "aws_iam_role" "eks" { }

# DO: Orchestration with modules
module "vpc" {
  source = "./modules/vpc"
}

module "eks" {
  source = "./modules/eks"
  vpc_id = module.vpc.vpc_id
}

module "rds" {
  source = "./modules/rds"
  vpc_id = module.vpc.vpc_id
}
```

### 4. Using `count` for Named Resources

```hcl
# DON'T: Removing "public-b" will recreate "private-a"!
variable "subnet_names" {
  default = ["public-a", "public-b", "private-a"]
}

resource "aws_subnet" "main" {
  count  = length(var.subnet_names)
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.subnet_names[count.index]
  }
}

# DO: Stable key-based addressing
variable "subnets" {
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
}

resource "aws_subnet" "main" {
  for_each = var.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name = each.key
  }
}
```

### 5. No State Locking

```hcl
# DON'T
terraform {
  backend "s3" {
    bucket = "my-tfstate"
    key    = "vpc/terraform.tfstate"
    # No DynamoDB table for locking!
  }
}

# DO
terraform {
  backend "s3" {
    bucket         = "my-tfstate"
    key            = "vpc/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"  # Prevents concurrent applies
    encrypt        = true
  }
}
```

### 6. Testing Only in Production

```bash
# DON'T: No tests, apply directly to production
terraform apply -auto-approve

# DO: Layered testing approach
# 1. Static analysis
tflint
terraform validate
checkov -d .

# 2. Unit tests
terraform test

# 3. Plan review
terraform plan -out=tfplan

# 4. Integration tests in dev
terraform apply -target=module.test_vpc

# 5. Production apply
terraform apply tfplan
```

---

## Quick Start Examples

### Example 1: Simple Terraform Module

```hcl
# modules/s3-bucket/main.tf
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# modules/s3-bucket/variables.tf
variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "enable_versioning" {
  description = "Enable versioning"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

# modules/s3-bucket/outputs.tf
output "bucket_id" {
  description = "The ID of the bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the bucket"
  value       = aws_s3_bucket.this.arn
}
```

### Example 2: Terragrunt Catalog/Live Structure

```
repo/
├── catalog/                    # Reusable modules
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── eks/
└── live/                       # Environment configs
    ├── dev/
    │   ├── terragrunt.hcl     # Environment config
    │   ├── vpc/
    │   │   └── terragrunt.hcl
    │   └── eks/
    │       └── terragrunt.hcl
    └── prod/
        ├── terragrunt.hcl
        ├── vpc/
        └── eks/
```

```hcl
# live/dev/vpc/terragrunt.hcl
terraform {
  source = "../../../catalog/vpc"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  cidr_block  = "10.0.0.0/16"
  environment = "dev"
}
```

### Example 3: Native Terraform Test

```hcl
# tests/s3-bucket.tftest.hcl
variables {
  bucket_name       = "test-bucket-12345"
  enable_versioning = true
}

run "validate_bucket_creation" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == var.bucket_name
    error_message = "Bucket name mismatch"
  }
}

run "create_bucket" {
  command = apply

  assert {
    condition     = aws_s3_bucket.this.id != ""
    error_message = "Bucket must be created"
  }
}

run "verify_versioning" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled"
  }
}
```

### Example 4: GitHub Actions CI/CD

```yaml
# .github/workflows/terraform.yml
name: Terraform CI/CD

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.11.0

      - name: Terraform fmt
        run: terraform fmt -check -recursive

      - name: Terraform init
        run: terraform init -backend=false

      - name: Terraform validate
        run: terraform validate

      - name: Run tflint
        uses: terraform-linters/setup-tflint@v4

      - run: tflint --init && tflint -f compact

      - name: Run checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform

  test:
    runs-on: ubuntu-latest
    needs: validate
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-west-2

      - name: Run Terraform tests
        run: terraform test

  plan:
    runs-on: ubuntu-latest
    needs: test
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-west-2

      - name: Terraform init
        run: terraform init

      - name: Terraform plan
        id: plan
        run: terraform plan -out=tfplan

  apply:
    runs-on: ubuntu-latest
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-west-2

      - name: Terraform init
        run: terraform init

      - name: Terraform apply
        run: terraform apply -auto-approve
```

---

## License

```
Copyright 2026 oh-my-claudecode

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

---

## Next Steps

1. **Read the reference files** that match your current task (see [Reference Files Navigation](#reference-files-navigation))
2. **Check [quick-reference.md](references/quick-reference.md)** for command cheat sheets
3. **Set up CI/CD** using [ci-cd-pipelines.md](references/ci-cd-pipelines.md)

---

**Skill Version:** 1.0.0
**Last Updated:** 2026-02-05
**Maintained By:** oh-my-claudecode
