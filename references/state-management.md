# State Management Reference

Complete guide to Terraform and Terragrunt state management, covering backends, locking, migration, and multi-account patterns.

---

## 1. Remote Backend Configuration

### S3 Backend (AWS)

**Complete backend configuration with DynamoDB locking:**

```hcl
# terraform/backend.tf
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "prod/vpc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # Optional: Server-side encryption with KMS
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/xxxxx"

    # Optional: Access logging
    acl = "private"
  }
}
```

**DynamoDB lock table setup:**

```hcl
# infrastructure/state-backend/dynamodb.tf
resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "terraform-state-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Environment = "global"
  }
}
```

**S3 bucket with versioning and lifecycle:**

```hcl
# infrastructure/state-backend/s3.tf
resource "aws_s3_bucket" "terraform_state" {
  bucket = "mycompany-terraform-state"

  tags = {
    Name        = "Terraform State Bucket"
    Environment = "global"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
```

### GCS Backend (Google Cloud)

```hcl
# terraform/backend.tf
terraform {
  backend "gcs" {
    bucket  = "mycompany-terraform-state"
    prefix  = "prod/vpc"

    # Optional: Customer-managed encryption key
    encryption_key = "projects/myproject/locations/global/keyRings/terraform/cryptoKeys/state"
  }
}
```

**GCS bucket setup:**

```hcl
resource "google_storage_bucket" "terraform_state" {
  name     = "mycompany-terraform-state"
  location = "US"

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.terraform_state.id
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }
}
```

### Azure Storage Backend

```hcl
# terraform/backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "mycompanytfstate"
    container_name       = "tfstate"
    key                  = "prod.vpc.tfstate"

    # Optional: Use Azure AD authentication
    use_azuread_auth = true
  }
}
```

### Terraform Cloud Backend

```hcl
# terraform/backend.tf
terraform {
  cloud {
    organization = "mycompany"

    workspaces {
      name = "prod-vpc"
      # Or use tags for dynamic workspace selection
      # tags = ["prod", "networking"]
    }
  }
}
```

---

## 2. State Locking

### DynamoDB Lock Attributes

The lock table must have:
- **Hash key**: `LockID` (String)
- **Attributes**: `Info`, `Who`, `Created`, `Operation`, `Path`, `Version`

### Lock Timeout Handling

**Default timeout**: 20 minutes

```bash
# Extend lock timeout (not recommended for regular use)
terraform apply -lock-timeout=30m
```

### Force Unlock (DANGEROUS)

**Only use when:**
- Previous operation crashed/terminated abnormally
- Lock holder confirmed no longer running
- After verifying no concurrent operations

```bash
# Get lock ID from error message
terraform force-unlock <lock-id>

# Example
terraform force-unlock a1b2c3d4-5678-90ab-cdef-1234567890ab
```

**Safe unlock workflow:**

```bash
# 1. Verify no operations running
ps aux | grep terraform

# 2. Check DynamoDB for lock info
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID": {"S": "mycompany-terraform-state/prod/vpc/terraform.tfstate-md5"}}'

# 3. Force unlock if safe
terraform force-unlock <lock-id>

# 4. Verify unlock succeeded
terraform plan  # Should not show lock error
```

---

## 3. State Migration

### Moved Blocks (Terraform 1.1+)

**Recommended approach for refactoring:**

```hcl
# Before: Old structure
resource "aws_instance" "web" {
  # ...
}

# After: New module structure with moved block
module "web_servers" {
  source = "./modules/web-server"
  # ...
}

moved {
  from = aws_instance.web
  to   = module.web_servers.aws_instance.this
}
```

**Multiple moves:**

```hcl
# Renaming and restructuring
moved {
  from = aws_instance.old_name
  to   = aws_instance.new_name
}

moved {
  from = aws_security_group.old_sg
  to   = module.networking.aws_security_group.main
}

moved {
  from = module.old_module
  to   = module.new_module
}
```

**Moved block workflow:**

```bash
# 1. Add moved blocks to configuration
# 2. Plan to verify moves
terraform plan  # Should show "# aws_instance.new_name has moved to..."

# 3. Apply to update state
terraform apply

# 4. Remove moved blocks after successful migration
# (Keep for one release cycle in production)
```

### Terraform State Commands

**List resources:**

```bash
# List all resources
terraform state list

# Filter by pattern
terraform state list 'aws_instance.*'
terraform state list 'module.vpc.*'
```

**Move resources:**

```bash
# Rename a resource
terraform state mv aws_instance.old_name aws_instance.new_name

# Move to module
terraform state mv aws_instance.web module.web_servers.aws_instance.this

# Move between state files
terraform state mv -state=old.tfstate -state-out=new.tfstate \
  aws_instance.web aws_instance.web

# Move entire module
terraform state mv module.old_module module.new_module
```

**Remove resources:**

```bash
# Remove from state (resource continues to exist in cloud)
terraform state rm aws_instance.old

# Remove all module resources
terraform state rm 'module.old_module.*'
```

**Show resource details:**

```bash
# Show specific resource
terraform state show aws_instance.web

# Show with JSON output
terraform state show -json aws_instance.web | jq
```

### Migrating Between Backends

**Local to S3 migration:**

```bash
# 1. Configure new backend
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket = "mycompany-terraform-state"
    key    = "prod/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}
EOF

# 2. Initialize with migration
terraform init -migrate-state

# Terraform will prompt:
# Do you want to copy existing state to the new backend? yes

# 3. Verify migration
terraform state list

# 4. Delete local state files (after verification)
rm terraform.tfstate*
```

**S3 to Terraform Cloud:**

```bash
# 1. Update backend configuration
terraform {
  cloud {
    organization = "mycompany"
    workspaces {
      name = "prod-vpc"
    }
  }
}

# 2. Login to Terraform Cloud
terraform login

# 3. Migrate state
terraform init -migrate-state

# 4. Verify in Terraform Cloud UI
```

### State Import Workflow

**Import existing resources:**

```bash
# 1. Write resource configuration
cat > imported.tf <<EOF
resource "aws_instance" "existing" {
  # Configuration will be populated after import
  ami           = "ami-xxxxx"
  instance_type = "t3.micro"
}
EOF

# 2. Import resource
terraform import aws_instance.existing i-1234567890abcdef0

# 3. Verify import
terraform state show aws_instance.existing

# 4. Align configuration with actual state
terraform plan  # Should show no changes

# 5. If changes shown, update configuration to match
```

**Bulk import script:**

```bash
#!/bin/bash
# import-vpc.sh - Import existing VPC resources

# VPC
terraform import aws_vpc.main vpc-xxxxx

# Subnets
terraform import 'aws_subnet.private[0]' subnet-xxxxx
terraform import 'aws_subnet.private[1]' subnet-yyyyy
terraform import 'aws_subnet.public[0]' subnet-zzzzz

# Route tables
terraform import aws_route_table.private rtb-xxxxx
terraform import aws_route_table.public rtb-yyyyy

# Internet Gateway
terraform import aws_internet_gateway.main igw-xxxxx

echo "Import complete. Run 'terraform plan' to verify."
```

---

## 4. Terragrunt State Patterns

### Auto-Generated Backend Config

**Terragrunt root configuration:**

```hcl
# terragrunt.hcl (root)
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }

  config = {
    bucket         = "mycompany-terraform-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-${get_aws_account_id()}"
  }
}
```

**Generated backend.tf:**

```hcl
# Auto-generated by Terragrunt
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state-123456789012"
    key            = "prod/us-east-1/vpc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-123456789012"
  }
}
```

### Environment-Based Bucket Naming

```hcl
# terragrunt.hcl
locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env      = local.env_vars.locals.environment
}

remote_state {
  backend = "s3"
  config = {
    bucket = "mycompany-tfstate-${local.env}-${get_aws_account_id()}"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### Cross-Account State Access

**State bucket with cross-account access:**

```hcl
# infrastructure/state-backend/s3-policy.tf
data "aws_iam_policy_document" "state_bucket_policy" {
  # Allow same account full access
  statement {
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
  }

  # Allow prod account to read dev state
  statement {
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::111111111111:role/TerraformRole"]
    }
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/dev/*"
    ]
  }
}
```

**Terragrunt cross-account dependency:**

```hcl
# prod/vpc/terragrunt.hcl
dependency "dev_vpc" {
  config_path = "../../dev/vpc"

  # Assume role in dev account
  iam_role = "arn:aws:iam::222222222222:role/TerraformRole"
}

inputs = {
  dev_vpc_id = dependency.dev_vpc.outputs.vpc_id
}
```

### State Bucket Per Environment

```hcl
# terragrunt.hcl
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_id   = local.account_vars.locals.account_id
  account_name = local.account_vars.locals.account_name
}

remote_state {
  backend = "s3"
  config = {
    # Separate bucket per account/environment
    bucket         = "tfstate-${local.account_name}-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tfstate-lock-${local.account_name}"

    # Use account-specific role
    role_arn = "arn:aws:iam::${local.account_id}:role/TerraformRole"
  }
}
```

---

## 5. State File Operations

### Inspection Commands

```bash
# List all resources
terraform state list

# Show resource details
terraform state show aws_instance.web

# Show entire state (JSON)
terraform show -json | jq

# Pull remote state locally
terraform state pull > terraform.tfstate.backup

# Push local state to remote
terraform state push terraform.tfstate
```

### State Manipulation

```bash
# Move resource to new address
terraform state mv aws_instance.old aws_instance.new

# Remove resource from state
terraform state rm aws_instance.old

# Replace provider address (for provider migrations)
terraform state replace-provider \
  registry.terraform.io/hashicorp/aws \
  registry.terraform.io/mycompany/aws

# Import existing resource
terraform import aws_instance.web i-1234567890abcdef0

# Refresh state (update attributes without applying changes)
terraform refresh  # Deprecated in Terraform 1.5+
terraform apply -refresh-only  # Recommended alternative
```

---

## 6. Backup Strategies

### S3 Versioning (Automatic)

```hcl
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

**Restore previous version:**

```bash
# List versions
aws s3api list-object-versions \
  --bucket mycompany-terraform-state \
  --prefix prod/vpc/terraform.tfstate

# Download specific version
aws s3api get-object \
  --bucket mycompany-terraform-state \
  --key prod/vpc/terraform.tfstate \
  --version-id <version-id> \
  terraform.tfstate.backup

# Push as current state (after verification)
terraform state push terraform.tfstate.backup
```

### Point-in-Time Recovery

**Enable S3 bucket recovery:**

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = "mycompany-terraform-state"

  # Versioning required for PITR
  versioning {
    enabled = true
  }

  # Lifecycle to retain versions
  lifecycle_rule {
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }
}
```

### Manual Backup Before Major Changes

```bash
#!/bin/bash
# backup-state.sh - Create timestamped backup before major operations

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./state-backups"
mkdir -p "$BACKUP_DIR"

# Pull current state
terraform state pull > "$BACKUP_DIR/terraform.tfstate.$TIMESTAMP"

echo "State backed up to $BACKUP_DIR/terraform.tfstate.$TIMESTAMP"

# Optional: Compress old backups
find "$BACKUP_DIR" -name "*.tfstate.*" -mtime +30 -exec gzip {} \;
```

---

## 7. Multi-Account/Multi-Region

### Separate State Per Account

```
.
├── accounts/
│   ├── dev/
│   │   ├── account.hcl          # account_id = "111111111111"
│   │   ├── us-east-1/
│   │   │   └── vpc/
│   │   │       └── terragrunt.hcl  # State: tfstate-dev-111111111111/dev/us-east-1/vpc
│   │   └── us-west-2/
│   ├── prod/
│   │   ├── account.hcl          # account_id = "222222222222"
│   │   ├── us-east-1/
│   │   └── us-west-2/
└── terragrunt.hcl  # Root config
```

### Cross-Account Role Assumption

**IAM role in target account:**

```hcl
# Target account: 222222222222
resource "aws_iam_role" "terraform" {
  name = "TerraformRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::111111111111:root"  # Source account
      }
      Action = "sts:AssumeRole"
    }]
  })
}
```

**Terragrunt configuration:**

```hcl
# prod/us-east-1/vpc/terragrunt.hcl
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::222222222222:role/TerraformRole"
  }
}
EOF
}

remote_state {
  backend = "s3"
  config = {
    bucket   = "tfstate-prod-222222222222"
    key      = "${path_relative_to_include()}/terraform.tfstate"
    region   = "us-east-1"
    role_arn = "arn:aws:iam::222222222222:role/TerraformRole"
  }
}
```

### Regional State Buckets

```hcl
# terragrunt.hcl
locals {
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region      = local.region_vars.locals.aws_region
}

remote_state {
  backend = "s3"
  config = {
    # Regional bucket for lower latency
    bucket = "mycompany-tfstate-${local.region}-${get_aws_account_id()}"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = local.region
  }
}
```

---

## 8. Troubleshooting

### State Lock Issues

**Symptoms:**
- "Error acquiring the state lock"
- Operations hang indefinitely

**Solutions:**

```bash
# 1. Check DynamoDB for lock info
aws dynamodb scan \
  --table-name terraform-state-lock \
  --filter-expression "attribute_exists(LockID)"

# 2. Verify no Terraform processes running
ps aux | grep terraform
pgrep -fl terraform

# 3. Force unlock (if safe)
terraform force-unlock <lock-id>

# 4. If DynamoDB shows stale lock, delete directly (last resort)
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID": {"S": "mycompany-terraform-state/prod/vpc/terraform.tfstate-md5"}}'
```

### Corrupt State Recovery

**Symptoms:**
- "Error loading state"
- "state snapshot was created by Terraform v..."
- Unexpected resource diffs

**Recovery workflow:**

```bash
# 1. Backup current state
terraform state pull > corrupted.tfstate

# 2. List S3 versions
aws s3api list-object-versions \
  --bucket mycompany-terraform-state \
  --prefix prod/vpc/terraform.tfstate

# 3. Download previous version
aws s3api get-object \
  --bucket mycompany-terraform-state \
  --key prod/vpc/terraform.tfstate \
  --version-id <good-version-id> \
  recovered.tfstate

# 4. Verify recovered state
terraform show recovered.tfstate

# 5. Push recovered state
terraform state push recovered.tfstate

# 6. Verify with plan
terraform plan
```

### State Drift Detection

**Automated drift detection script:**

```bash
#!/bin/bash
# detect-drift.sh - Check for infrastructure drift

set -euo pipefail

echo "Checking for state drift..."

# Run refresh-only to detect changes
if terraform plan -refresh-only -detailed-exitcode > /dev/null 2>&1; then
  echo "✅ No drift detected"
  exit 0
else
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 2 ]; then
    echo "⚠️  Drift detected!"
    terraform plan -refresh-only
    exit 1
  else
    echo "❌ Error running drift detection"
    exit $EXIT_CODE
  fi
fi
```

**CI/CD drift detection:**

```yaml
# .github/workflows/drift-detection.yml
name: Drift Detection

on:
  schedule:
    - cron: '0 9 * * *'  # Daily at 9 AM

jobs:
  detect-drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}

      - name: Check for drift
        run: |
          terraform init
          terraform plan -refresh-only -detailed-exitcode || \
            (echo "Drift detected! Check GitHub Actions logs." && exit 1)
```

**Manual drift investigation:**

```bash
# 1. Run refresh to see what changed
terraform plan -refresh-only

# 2. Show specific resource state
terraform state show aws_instance.web

# 3. Pull actual AWS state
aws ec2 describe-instances --instance-ids i-xxxxx | jq

# 4. Compare and identify drift source
# - Manual change in console?
# - Another tool/process modifying resources?
# - Terraform configuration out of sync?

# 5. Remediate
# Option A: Update Terraform config to match reality
# Option B: Re-apply Terraform to fix drift
terraform apply
```

---

## Best Practices Summary

1. **Always use remote state** for team collaboration
2. **Enable versioning** on state buckets (S3/GCS)
3. **Use state locking** (DynamoDB/native backend locking)
4. **Separate state per environment** (dev/staging/prod)
5. **Use Terragrunt** for DRY backend configuration
6. **Backup state before major changes** (migrations, imports)
7. **Use `moved` blocks** instead of manual `state mv` when possible
8. **Never edit state files manually** (use `terraform state` commands)
9. **Monitor for drift** with automated checks
10. **Secure state files** (encryption at rest, restrict access)
