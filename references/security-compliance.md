# Security & Compliance Reference

> Comprehensive security best practices for Terraform/Terragrunt infrastructure

## Table of Contents
- [Secrets Management](#secrets-management)
- [State File Security](#state-file-security)
- [Encryption Patterns](#encryption-patterns)
- [Security Scanning Tools](#security-scanning-tools)
- [Compliance Checking](#compliance-checking)
- [Least Privilege Patterns](#least-privilege-patterns)
- [Common Security Pitfalls](#common-security-pitfalls)
- [Code Review Security Checklist](#code-review-security-checklist)

---

## Secrets Management

### Write-Only Arguments (Terraform 1.11+)

**Best practice for sensitive input variables:**

```hcl
# variables.tf
variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
  write_only  = true  # Prevents reading back value
}

# outputs.tf - NEVER output sensitive values
output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

# WRONG: Never output secrets
output "db_password" {
  value = var.db_password  # ❌ Security violation
}
```

### AWS Secrets Manager Integration

```hcl
# secrets.tf
resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.environment}/database/master_password"
  description = "RDS master password"

  recovery_window_in_days = 7

  tags = {
    Environment = var.environment
    Compliance  = "PCI-DSS"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Retrieve secret in application (not Terraform)
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
}

resource "aws_db_instance" "main" {
  password = data.aws_secretsmanager_secret_version.db_password.secret_string

  # Ensure secret is created first
  depends_on = [aws_secretsmanager_secret_version.db_password]
}
```

### HashiCorp Vault Integration

```hcl
# provider.tf
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "vault" {
  address = "https://vault.company.com"
  # Auth via VAULT_TOKEN environment variable
}

# vault.tf
data "vault_generic_secret" "db_credentials" {
  path = "secret/data/${var.environment}/database"
}

resource "aws_db_instance" "main" {
  username = data.vault_generic_secret.db_credentials.data["username"]
  password = data.vault_generic_secret.db_credentials.data["password"]
}

# Store generated secrets back in Vault
resource "vault_generic_secret" "api_key" {
  path = "secret/${var.environment}/api_key"

  data_json = jsonencode({
    api_key    = random_password.api_key.result
    created_at = timestamp()
  })
}
```

### Environment Variables (CI/CD Only)

```hcl
# variables.tf
variable "github_token" {
  description = "GitHub PAT for provider authentication"
  type        = string
  sensitive   = true

  # Validate presence but never log
  validation {
    condition     = length(var.github_token) > 0
    error_message = "github_token must be provided via TF_VAR_github_token"
  }
}

# .github/workflows/terraform.yml
env:
  TF_VAR_github_token: ${{ secrets.GH_TOKEN }}
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### What to NEVER Do

```hcl
# ❌ NEVER: Hardcoded secrets
resource "aws_db_instance" "main" {
  password = "MyP@ssw0rd123"  # SECURITY VIOLATION
}

# ❌ NEVER: Secrets in version control
# terraform.tfvars
db_password = "secret123"  # DO NOT COMMIT

# ❌ NEVER: Secrets in outputs without sensitive flag
output "api_key" {
  value = var.api_key  # Missing sensitive = true
}

# ✅ CORRECT: Always mark outputs as sensitive
output "api_key" {
  value     = var.api_key
  sensitive = true
}
```

**`.gitignore` must include:**
```gitignore
*.tfvars
*.tfvars.json
!terraform.tfvars.example
.terraform/
terraform.tfstate*
.terragrunt-cache/
```

---

## State File Security

### Encryption at Rest (S3 SSE-KMS)

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "prod/vpc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true  # Enable SSE-S3 or SSE-KMS
    kms_key_id     = "arn:aws:kms:us-east-1:123456789012:key/abc-def"
    dynamodb_table = "terraform-state-lock"

    # Workspace isolation
    workspace_key_prefix = "workspaces"
  }
}

# S3 bucket configuration (separate module)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "company-terraform-state"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true  # Reduces KMS costs
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

### State Locking (DynamoDB)

```hcl
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

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  tags = {
    Purpose = "Terraform state locking"
  }
}
```

### Access Controls (IAM Policies)

```hcl
# Least privilege IAM policy for Terraform execution
data "aws_iam_policy_document" "terraform_state_access" {
  # Read state
  statement {
    sid = "ReadState"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
  }

  # Write state (restricted to CI/CD role)
  statement {
    sid = "WriteState"
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  # State locking
  statement {
    sid = "StateLocking"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = [aws_dynamodb_table.terraform_state_lock.arn]
  }

  # KMS decryption
  statement {
    sid = "KMSDecrypt"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey"
    ]
    resources = [aws_kms_key.terraform_state.arn]
  }
}
```

### State File Backup

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "state-backup"
    status = "Enabled"

    # Transition old versions to cheaper storage
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    # Keep 100 versions
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}
```

---

## Encryption Patterns

### S3 Bucket Encryption (Complete Example)

```hcl
# s3-encrypted.tf
resource "aws_s3_bucket" "secure_data" {
  bucket = "company-secure-data-${var.environment}"
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for audit trail
resource "aws_s3_bucket_versioning" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enforce encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

# Deny unencrypted uploads
resource "aws_s3_bucket_policy" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedObjectUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.secure_data.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.secure_data.arn,
          "${aws_s3_bucket.secure_data.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Enable logging
resource "aws_s3_bucket_logging" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/"
}
```

### RDS Encryption

```hcl
resource "aws_db_instance" "secure_db" {
  identifier = "secure-db-${var.environment}"

  # Encryption at rest
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # Encryption in transit
  ca_cert_identifier = "rds-ca-rsa2048-g1"

  # Network isolation
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.private.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Audit logging
  enabled_cloudwatch_logs_exports = [
    "audit",
    "error",
    "general",
    "slowquery"
  ]

  # Backup with encryption
  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  copy_tags_to_snapshot   = true

  deletion_protection = true
}
```

### EBS Encryption

```hcl
# Enable EBS encryption by default (account-level)
resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "default" {
  key_arn = aws_kms_key.ebs.arn
}

# Instance with encrypted volumes
resource "aws_instance" "secure_app" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  root_block_device {
    encrypted   = true
    kms_key_id  = aws_kms_key.ebs.arn
    volume_type = "gp3"
  }

  ebs_block_device {
    device_name = "/dev/sdf"
    encrypted   = true
    kms_key_id  = aws_kms_key.ebs.arn
  }
}
```

### EKS Secrets Encryption

```hcl
resource "aws_eks_cluster" "secure_cluster" {
  name     = "secure-cluster"
  role_arn = aws_iam_role.eks_cluster.arn

  # Envelope encryption for Kubernetes secrets
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false  # Private cluster
    subnet_ids              = aws_subnet.private[*].id
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }
}
```

---

## Security Scanning Tools

### tfsec Usage and Rules

```bash
# Install tfsec
brew install tfsec

# Basic scan
tfsec .

# Scan with severity filtering
tfsec --minimum-severity HIGH .

# Output formats
tfsec --format json --out results.json .
tfsec --format junit --out results.xml .
tfsec --format sarif --out results.sarif .

# Exclude specific checks
tfsec --exclude aws-s3-enable-bucket-logging .

# Soft fail (warnings only)
tfsec --soft-fail .
```

**Inline exceptions:**
```hcl
resource "aws_s3_bucket" "public_website" {
  # tfsec:ignore:aws-s3-block-public-acls Intentionally public for static website
  bucket = "company-public-website"
}
```

**Custom tfsec checks** (`.tfsec/custom_checks.yaml`):
```yaml
checks:
  - code: company-aws-001
    description: All production resources must have backup tags
    impact: Data loss risk
    resolution: Add backup tag
    requiredTypes:
      - resource
    requiredLabels:
      - aws_instance
      - aws_db_instance
    severity: HIGH
    matchSpec:
      name: tags
      action: contains
      value: backup
    errorMessage: Resource missing required 'backup' tag
```

### checkov Usage and Policies

```bash
# Install checkov
pip install checkov

# Scan Terraform
checkov -d .

# Specific frameworks
checkov --framework terraform -d .
checkov --framework terragrunt -d .

# Skip specific checks
checkov -d . --skip-check CKV_AWS_20

# Output formats
checkov -d . -o json --output-file results.json
checkov -d . -o sarif --output-file results.sarif
```

**Inline suppression:**
```hcl
resource "aws_security_group_rule" "allow_all" {
  # checkov:skip=CKV_AWS_260:Legacy system requires open access
  type        = "ingress"
  cidr_blocks = ["0.0.0.0/0"]
}
```

**Custom policies** (`.checkov.yaml`):
```yaml
framework: terraform
skip-check:
  - CKV_AWS_20  # S3 bucket logging
  - CKV_AWS_21  # S3 versioning

external-checks-dir:
  - ./custom_policies
```

### trivy Config Scanning

```bash
# Install trivy
brew install trivy

# Scan Terraform
trivy config .

# Scan with severity filtering
trivy config --severity HIGH,CRITICAL .

# Output formats
trivy config -f json -o results.json .
trivy config -f sarif -o results.sarif .

# Ignore specific checks
trivy config --skip-policy AVD-AWS-0086 .
```

### Pre-commit Hook Configuration

**`.pre-commit-config.yaml`:**
```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.88.4
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_docs
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
      - id: terraform_tfsec
        args:
          - --args=--minimum-severity=HIGH
      - id: terraform_checkov
        args:
          - --args=--framework terraform --skip-check CKV_AWS_20

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: detect-private-key
      - id: check-merge-conflict
      - id: end-of-file-fixer
      - id: trailing-whitespace
```

```bash
# Install pre-commit
pip install pre-commit

# Setup hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

---

## Compliance Checking

### terraform-compliance

```bash
# Install
pip install terraform-compliance

# Run compliance tests
terraform-compliance -f compliance/ -p plan.json
```

**Compliance policy** (`compliance/s3_encryption.feature`):
```gherkin
Feature: S3 bucket encryption
  In order to protect data at rest
  As a security team
  We want to ensure all S3 buckets are encrypted

  Scenario: All S3 buckets must be encrypted
    Given I have aws_s3_bucket defined
    Then it must contain server_side_encryption_configuration

  Scenario: S3 buckets must use KMS encryption
    Given I have aws_s3_bucket_server_side_encryption_configuration defined
    When it contains rule
    Then it must contain apply_server_side_encryption_by_default
    And it must contain sse_algorithm
    And its value must be aws:kms
```

### OPA/Conftest

```bash
# Install conftest
brew install conftest

# Test Terraform plan
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
conftest test plan.json
```

**Policy** (`policy/s3.rego`):
```rego
package main

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket"
  not resource.change.after.server_side_encryption_configuration
  msg := sprintf("S3 bucket '%s' must be encrypted", [resource.address])
}

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket_public_access_block"
  settings := resource.change.after
  settings.block_public_acls != true
  msg := sprintf("S3 bucket '%s' must block public ACLs", [resource.address])
}
```

### Sentinel (HCP Terraform)

```hcl
# sentinel.hcl
policy "enforce-mandatory-tags" {
  source            = "./enforce-mandatory-tags.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "restrict-aws-instance-type" {
  source            = "./restrict-aws-instance-type.sentinel"
  enforcement_level = "soft-mandatory"
}
```

**Policy** (`enforce-mandatory-tags.sentinel`):
```python
import "tfplan/v2" as tfplan

mandatory_tags = ["Environment", "Owner", "CostCenter"]

validate_tags = func(resource) {
  tags = resource.change.after.tags else {}
  for mandatory_tags as tag {
    if tag not in keys(tags) {
      return false
    }
  }
  return true
}

main = rule {
  all tfplan.resource_changes as _, rc {
    rc.mode is "managed" and
    rc.type in ["aws_instance", "aws_db_instance", "aws_s3_bucket"] implies
    validate_tags(rc)
  }
}
```

---

## Least Privilege Patterns

### Security Group Rules (Explicit, Minimal)

```hcl
# ❌ WRONG: Overly permissive
resource "aws_security_group_rule" "bad" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
}

# ✅ CORRECT: Explicit and minimal
resource "aws_security_group" "app" {
  name        = "app-sg"
  description = "Application security group"
  vpc_id      = aws_vpc.main.id
}

# Allow HTTPS from ALB only
resource "aws_security_group_rule" "app_from_alb" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.app.id
  description              = "HTTPS from ALB"
}

# Allow PostgreSQL from app tier only
resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.db.id
  description              = "PostgreSQL from app tier"
}

# Egress: Explicit allow (deny by default)
resource "aws_security_group_rule" "app_to_db" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  destination_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.app.id
  description              = "PostgreSQL to database"
}
```

### IAM Role Policies

```hcl
# ✅ CORRECT: Least privilege IAM policy
data "aws_iam_policy_document" "lambda_execution" {
  # Read from specific S3 bucket
  statement {
    sid = "ReadS3Bucket"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/data/*"  # Specific prefix
    ]
  }

  # Write to CloudWatch Logs (scoped to function)
  statement {
    sid = "WriteLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.main.function_name}:*"
    ]
  }

  # Query DynamoDB table (no admin actions)
  statement {
    sid = "QueryDynamoDB"
    actions = [
      "dynamodb:Query",
      "dynamodb:GetItem"
    ]
    resources = [aws_dynamodb_table.main.arn]
  }
}

resource "aws_iam_role_policy" "lambda_execution" {
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_execution.json
}
```

### Cross-Account Role Assumption

```hcl
# Target account: Define assumable role
resource "aws_iam_role" "cross_account" {
  name = "CrossAccountReadOnly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::SOURCE_ACCOUNT_ID:role/TrustedRole"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.external_id  # Prevent confused deputy
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cross_account" {
  role       = aws_iam_role.cross_account.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Source account: Role that can assume
data "aws_iam_policy_document" "assume_cross_account" {
  statement {
    sid     = "AssumeCrossAccountRole"
    actions = ["sts:AssumeRole"]
    resources = [
      "arn:aws:iam::TARGET_ACCOUNT_ID:role/CrossAccountReadOnly"
    ]
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}
```

---

## Common Security Pitfalls

### Open Security Groups (0.0.0.0/0)

```hcl
# ❌ CRITICAL: Never allow unrestricted access
resource "aws_security_group_rule" "allow_all" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # Entire internet!
}

# ✅ CORRECT: Restrict to known IPs
resource "aws_security_group_rule" "ssh_from_office" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [
    "203.0.113.10/32",  # Office IP
    "203.0.113.20/32"   # VPN gateway
  ]
  description = "SSH from office network"
}

# ✅ BETTER: Use AWS Systems Manager Session Manager
# No inbound SSH required at all
```

### Public S3 Buckets

```hcl
# ❌ CRITICAL: Unintentionally public bucket
resource "aws_s3_bucket" "data" {
  bucket = "sensitive-data"
  acl    = "public-read"  # NEVER use this
}

# ✅ CORRECT: Block all public access
resource "aws_s3_bucket" "data" {
  bucket = "sensitive-data"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# If truly public (static website), be explicit
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.website.arn}/*"
    }]
  })
}
```

### Unencrypted Storage

```hcl
# ❌ HIGH: Unencrypted EBS volume
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  root_block_device {
    volume_size = 20
    # Missing: encrypted = true
  }
}

# ✅ CORRECT: Always encrypt
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  root_block_device {
    encrypted   = true
    kms_key_id  = aws_kms_key.ebs.arn
    volume_size = 20
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"  # IMDSv2 only
  }
}
```

### Missing Logging

```hcl
# ❌ MEDIUM: No audit trail
resource "aws_s3_bucket" "data" {
  bucket = "company-data"
}

# ✅ CORRECT: Enable comprehensive logging
resource "aws_s3_bucket" "data" {
  bucket = "company-data"
}

resource "aws_s3_bucket_logging" "data" {
  bucket = aws_s3_bucket.data.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/data/"
}

resource "aws_cloudtrail" "main" {
  name           = "company-audit-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.data.arn}/"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }
}
```

---

## Code Review Security Checklist

Use this checklist for all Terraform/Terragrunt code reviews:

### Secrets & Credentials
- [ ] No hardcoded passwords, API keys, or tokens
- [ ] Sensitive variables marked with `sensitive = true`
- [ ] Write-only variables used where appropriate (`write_only = true`)
- [ ] Secrets stored in Secrets Manager or Vault
- [ ] No secrets in outputs (or properly marked sensitive)
- [ ] `.gitignore` includes `*.tfvars` and state files

### Encryption
- [ ] S3 buckets have encryption enabled (SSE-KMS preferred)
- [ ] RDS instances have `storage_encrypted = true`
- [ ] EBS volumes have `encrypted = true`
- [ ] SNS/SQS have encryption configured
- [ ] EKS secrets encryption enabled
- [ ] State file encryption configured

### Network Security
- [ ] Security groups follow least privilege (no `0.0.0.0/0` unless justified)
- [ ] Database instances are not publicly accessible
- [ ] Resources in private subnets where appropriate
- [ ] NACLs configured for additional defense
- [ ] VPC flow logs enabled
- [ ] TLS 1.2+ enforced for all endpoints

### Access Control
- [ ] IAM policies follow least privilege principle
- [ ] No wildcard actions (`*`) or resources (`*`)
- [ ] MFA required for privileged operations
- [ ] Cross-account roles use ExternalId
- [ ] Service roles scoped to specific resources
- [ ] Assume role policies restrict trusted principals

### Logging & Monitoring
- [ ] CloudTrail enabled for audit logging
- [ ] S3 access logging configured
- [ ] VPC flow logs enabled
- [ ] RDS/Aurora audit logs enabled
- [ ] Lambda logs written to CloudWatch
- [ ] Alarms configured for security events

### State Management
- [ ] State file encryption enabled
- [ ] State locking configured (DynamoDB)
- [ ] State bucket versioning enabled
- [ ] State bucket access restricted (IAM policies)
- [ ] Workspace isolation properly configured

### Compliance
- [ ] All resources tagged (Environment, Owner, etc.)
- [ ] Backup retention policies configured
- [ ] Resource naming follows standards
- [ ] Cost allocation tags present
- [ ] Compliance policies tested (terraform-compliance, OPA)

### Scanning & Testing
- [ ] `tfsec` scan passed (HIGH+ issues resolved)
- [ ] `checkov` scan passed (CRITICAL issues resolved)
- [ ] Pre-commit hooks configured
- [ ] Terraform validate successful
- [ ] Plan reviewed for unexpected changes

### Documentation
- [ ] README explains security requirements
- [ ] Inline comments for security exceptions
- [ ] Runbook for security incident response
- [ ] Architecture diagram includes security boundaries

---

**Key Takeaways:**

1. **Never hardcode secrets** - Use Secrets Manager, Vault, or environment variables
2. **Encrypt everything** - At rest and in transit
3. **Least privilege always** - Explicit, minimal permissions
4. **Scan early, scan often** - Integrate tfsec/checkov into CI/CD
5. **State file security** - Encryption, versioning, access control
6. **Audit everything** - Logging, monitoring, compliance checks
