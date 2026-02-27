# CI/CD Pipelines for Terraform & Terragrunt

> **Part of:** [unified-terraform-terragrunt skill](../SKILL.md)
> **Purpose:** Complete CI/CD pipeline patterns with cloud authentication, security scanning, and cost optimization

This document consolidates CI/CD best practices from terraform-skill, terragrunt-skill, and devops-iac-engineer, providing production-ready pipeline templates for both Terraform and Terragrunt workflows.

---

## Table of Contents

1. [Recommended Workflow Stages](#recommended-workflow-stages)
2. [GitHub Actions Examples](#github-actions-examples)
3. [GitLab CI Examples](#gitlab-ci-examples)
4. [Cost Optimization Strategy](#cost-optimization-strategy)
5. [Security Scanning Integration](#security-scanning-integration)
6. [Atlantis Integration](#atlantis-integration)
7. [Best Practices](#best-practices)

---

## Recommended Workflow Stages

### Standard Pipeline Flow

```
┌──────────┐   ┌──────────┐   ┌──────┐   ┌───────┐
│ Validate │──▶│   Test   │──▶│ Plan │──▶│ Apply │
│          │   │          │   │      │   │       │
└──────────┘   └──────────┘   └──────┘   └───────┘
     │              │             │           │
     ├─ Format      ├─ Native     ├─ Cost    ├─ Approval
     ├─ Syntax      ├─ Terratest  ├─ Scan    └─ State lock
     └─ Lint        └─ Security   └─ Comment
```

### Stage Breakdown

| Stage | Purpose | Tools | When |
|-------|---------|-------|------|
| **Validate** | Syntax, format, lint | `terraform fmt`, `terraform validate`, `tflint` | Every PR |
| **Test** | Unit & integration tests | `terraform test`, Terratest, mocking | PR (unit), main (integration) |
| **Plan** | Generate execution plan | `terraform plan`, `terragrunt plan` | Every PR & main |
| **Apply** | Deploy infrastructure | `terraform apply`, `terragrunt apply` | Main branch only, with approval |

### Key Principles

1. **Separate plan and apply jobs** - Always review plans before applying
2. **PR comments with plan output** - Enable team review without CLI access
3. **Approval gates for production** - Manual approval for critical environments
4. **State locking** - Prevent concurrent modifications
5. **Parallel execution control** - Balance speed and rate limits

---

## GitHub Actions Examples

### Terraform-Only Workflow

```yaml
# .github/workflows/terraform.yml
name: Terraform CI/CD

on:
  push:
    branches: [main]
  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform.yml'

env:
  TF_VERSION: '1.9.0'
  TF_ROOT: './terraform/environments/dev'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Init
        run: terraform init -backend=false
        working-directory: ${{ env.TF_ROOT }}

      - name: Terraform Validate
        run: terraform validate
        working-directory: ${{ env.TF_ROOT }}

      - name: TFLint
        run: |
          curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
          tflint --init
          tflint
        working-directory: ${{ env.TF_ROOT }}

  test:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Run Terraform Tests (Mocked)
        run: terraform test
        working-directory: ${{ env.TF_ROOT }}

      # Integration tests only on main branch to control costs
      - name: Setup Go
        if: github.ref == 'refs/heads/main'
        uses: actions/setup-go@v5
        with:
          go-version: '1.21'

      - name: Run Terratest Integration
        if: github.ref == 'refs/heads/main'
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: |
          cd tests
          go test -v -timeout 30m -parallel 4

  security-scan:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Trivy Config Scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          scan-ref: ${{ env.TF_ROOT }}
          exit-code: 1
          severity: 'CRITICAL,HIGH'

      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: ${{ env.TF_ROOT }}
          framework: terraform
          soft_fail: false

      - name: Run tfsec
        uses: aquasecurity/tfsec-action@v1.0.3
        with:
          working_directory: ${{ env.TF_ROOT }}
          soft_fail: false

  plan:
    needs: [test, security-scan]
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111111111111:role/TerraformCrossAccount
          aws-region: us-east-1

      - name: Terraform Init
        run: terraform init
        working-directory: ${{ env.TF_ROOT }}

      - name: Terraform Plan
        id: plan
        run: terraform plan -out=tfplan -no-color
        working-directory: ${{ env.TF_ROOT }}
        continue-on-error: true

      - name: Save Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: ${{ env.TF_ROOT }}/tfplan
          retention-days: 7

      - name: Comment PR with Plan
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const output = `#### Terraform Plan 📋

            <details><summary>Show Plan</summary>

            \`\`\`terraform
            ${{ steps.plan.outputs.stdout }}
            \`\`\`

            </details>

            *Workflow: \`${{ github.workflow }}\`, Action: \`${{ github.event_name }}\`*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })

  apply:
    needs: plan
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment:
      name: production
      url: https://console.aws.amazon.com
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::222222222222:role/TerraformCrossAccount
          aws-region: us-east-1

      - name: Terraform Init
        run: terraform init
        working-directory: ${{ env.TF_ROOT }}

      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: ${{ env.TF_ROOT }}

      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan
        working-directory: ${{ env.TF_ROOT }}
```

### Terragrunt Stack Workflow

```yaml
# .github/workflows/terragrunt.yml
name: Terragrunt Stack CI/CD

on:
  push:
    branches: [main]
  pull_request:
    paths:
      - 'infrastructure-live/**'
      - '.github/workflows/terragrunt.yml'

env:
  TG_VERSION: '0.55.0'
  TF_VERSION: '1.9.0'
  TG_STACK_PATH: './infrastructure-live/non-prod/us-east-1/staging/my-service'
  TG_PARALLELISM: '10'
  # Provider caching for performance
  TG_PROVIDER_CACHE: '1'
  TG_PROVIDER_CACHE_DIR: '/tmp/provider-cache'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Setup Terragrunt
        run: |
          wget -q https://github.com/gruntwork-io/terragrunt/releases/download/v${{ env.TG_VERSION }}/terragrunt_linux_amd64
          chmod +x terragrunt_linux_amd64
          sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

      - name: Terragrunt Format Check
        run: terragrunt hclfmt --terragrunt-check
        working-directory: ${{ env.TG_STACK_PATH }}

      - name: Terragrunt Validate
        run: terragrunt validate-inputs --terragrunt-non-interactive
        working-directory: ${{ env.TG_STACK_PATH }}

  plan:
    needs: validate
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform & Terragrunt
        run: |
          # Terraform
          wget -q https://releases.hashicorp.com/terraform/${{ env.TF_VERSION }}/terraform_${{ env.TF_VERSION }}_linux_amd64.zip
          unzip -q terraform_${{ env.TF_VERSION }}_linux_amd64.zip
          sudo mv terraform /usr/local/bin/

          # Terragrunt
          wget -q https://github.com/gruntwork-io/terragrunt/releases/download/v${{ env.TG_VERSION }}/terragrunt_linux_amd64
          chmod +x terragrunt_linux_amd64
          sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

      - name: Cache Provider Plugins
        uses: actions/cache@v4
        with:
          path: ${{ env.TG_PROVIDER_CACHE_DIR }}
          key: ${{ runner.os }}-terragrunt-${{ hashFiles('**/.terraform.lock.hcl') }}
          restore-keys: |
            ${{ runner.os }}-terragrunt-

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111111111111:role/TerraformCrossAccount
          aws-region: us-east-1

      - name: Terragrunt Stack Plan
        id: plan
        run: |
          mkdir -p ${{ env.TG_PROVIDER_CACHE_DIR }}
          terragrunt stack run plan \
            --parallelism ${{ env.TG_PARALLELISM }} \
            --terragrunt-non-interactive
        working-directory: ${{ env.TG_STACK_PATH }}
        continue-on-error: true

      - name: Save Stack Plans
        uses: actions/upload-artifact@v4
        with:
          name: stack-plans
          path: ${{ env.TG_STACK_PATH }}/.terragrunt-stack/**/tfplan
          retention-days: 7

  apply:
    needs: plan
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment:
      name: staging
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform & Terragrunt
        run: |
          wget -q https://releases.hashicorp.com/terraform/${{ env.TF_VERSION }}/terraform_${{ env.TF_VERSION }}_linux_amd64.zip
          unzip -q terraform_${{ env.TF_VERSION }}_linux_amd64.zip
          sudo mv terraform /usr/local/bin/

          wget -q https://github.com/gruntwork-io/terragrunt/releases/download/v${{ env.TG_VERSION }}/terragrunt_linux_amd64
          chmod +x terragrunt_linux_amd64
          sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

      - name: Cache Provider Plugins
        uses: actions/cache@v4
        with:
          path: ${{ env.TG_PROVIDER_CACHE_DIR }}
          key: ${{ runner.os }}-terragrunt-${{ hashFiles('**/.terraform.lock.hcl') }}

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111111111111:role/TerraformCrossAccount
          aws-region: us-east-1

      - name: Terragrunt Stack Apply
        run: |
          mkdir -p ${{ env.TG_PROVIDER_CACHE_DIR }}
          terragrunt stack run apply \
            --parallelism ${{ env.TG_PARALLELISM }} \
            --terragrunt-non-interactive
        working-directory: ${{ env.TG_STACK_PATH }}
```

### Multi-Environment Matrix Strategy

```yaml
# .github/workflows/terraform-matrix.yml
name: Multi-Environment Terraform

on:
  push:
    branches: [main]
  pull_request:

strategy:
  matrix:
    environment:
      - name: dev
        account_id: '111111111111'
        region: us-east-1
      - name: staging
        account_id: '222222222222'
        region: us-east-1
      - name: prod
        account_id: '333333333333'
        region: us-east-1

jobs:
  plan:
    runs-on: ubuntu-latest
    strategy:
      matrix: ${{ fromJson(strategy.matrix) }}
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS for ${{ matrix.environment.name }}
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ matrix.environment.account_id }}:role/TerraformCrossAccount
          aws-region: ${{ matrix.environment.region }}

      # ... plan steps
```

### GCP Workload Identity (OIDC)

```yaml
# .github/workflows/terraform-gcp.yml
name: Terraform GCP

on:
  push:
    branches: [main]
  pull_request:

env:
  GCP_PROJECT_ID: 'my-project-dev'
  GCP_REGION: 'us-central1'

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: 'projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
          service_account: 'sa-tf-admin@my-project-dev.iam.gserviceaccount.com'

      - name: Setup Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Terraform Plan
        run: |
          terraform init
          terraform plan -out=tfplan
        working-directory: ./terraform/gcp/dev
```

---

## GitLab CI Examples

### Terraform Pipeline with OIDC

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - test
  - security
  - plan
  - apply

variables:
  TF_VERSION: '1.9.0'
  TF_ROOT: ${CI_PROJECT_DIR}/terraform/environments/dev
  AWS_REGION: us-east-1
  AWS_ACCOUNT_ID: '111111111111'
  AWS_ROLE_NAME: TerraformCrossAccount

default:
  image: hashicorp/terraform:${TF_VERSION}

# Reusable template for AWS OIDC auth
.aws-oidc-auth:
  id_tokens:
    AWS_OIDC_TOKEN:
      aud: https://gitlab.com
  before_script:
    - |
      # Install AWS CLI
      apk add --no-cache python3 py3-pip
      pip3 install --no-cache-dir awscli

      # Assume role with OIDC
      export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}"

      CREDS=$(aws sts assume-role-with-web-identity \
        --role-arn "$ROLE_ARN" \
        --role-session-name "gitlab-ci-${CI_PIPELINE_ID}" \
        --web-identity-token "$AWS_OIDC_TOKEN" \
        --duration-seconds 3600 \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text)

      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')

      echo "Authenticated to AWS account: ${AWS_ACCOUNT_ID}"

validate:fmt:
  stage: validate
  script:
    - terraform fmt -check -recursive
  only:
    - merge_requests
    - main

validate:syntax:
  stage: validate
  script:
    - cd ${TF_ROOT}
    - terraform init -backend=false
    - terraform validate
  only:
    - merge_requests
    - main

test:unit:
  stage: test
  script:
    - cd ${TF_ROOT}
    - terraform init -backend=false
    - terraform test
  only:
    - merge_requests
    - main

security:trivy:
  stage: security
  image: aquasec/trivy:latest
  script:
    - trivy config --exit-code 1 --severity HIGH,CRITICAL ${TF_ROOT}
  allow_failure: true

security:checkov:
  stage: security
  image: bridgecrew/checkov:latest
  script:
    - checkov -d ${TF_ROOT} --framework terraform --soft-fail
  artifacts:
    reports:
      junit: checkov-report.xml

plan:
  extends: .aws-oidc-auth
  stage: plan
  script:
    - cd ${TF_ROOT}
    - terraform init
    - terraform plan -out=tfplan
  artifacts:
    paths:
      - ${TF_ROOT}/tfplan
    expire_in: 7 days
  only:
    - merge_requests
    - main

apply:
  extends: .aws-oidc-auth
  stage: apply
  script:
    - cd ${TF_ROOT}
    - terraform init
    - terraform apply -auto-approve tfplan
  dependencies:
    - plan
  only:
    - main
  when: manual
  environment:
    name: production
    action: start
```

### Terragrunt Pipeline with GCP OIDC

```yaml
# .gitlab-ci-terragrunt-gcp.yml
stages:
  - checks
  - plan
  - apply

variables:
  TG_VERSION: '0.55.0'
  TF_VERSION: '1.9.0'
  TG_STACK_PATH: './infrastructure-live/gcp-dev/us-east4/my-service'
  TG_PARALLELISM: '10'
  TG_PROVIDER_CACHE: '1'
  TG_PROVIDER_CACHE_DIR: '/tmp/provider-cache'
  GC_PROJECT_NUMBER: '123456789012'
  SERVICE_ACCOUNT: 'sa-tf-admin@my-project-dev.iam.gserviceaccount.com'
  WORKLOAD_IDENTITY_POOL: 'gitlab-pool'
  WORKLOAD_IDENTITY_PROVIDER: 'gitlab-provider'

.gcp-oidc-auth:
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: https://iam.googleapis.com/projects/${GC_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL}/providers/${WORKLOAD_IDENTITY_PROVIDER}
  before_script:
    - |
      # Install gcloud
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
      curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
      apt-get update && apt-get install -y google-cloud-sdk

      # Write OIDC token
      echo $GITLAB_OIDC_TOKEN > ${CI_BUILDS_DIR}/.workload_identity.jwt

      # Create workload identity config
      cat << EOF > ${CI_BUILDS_DIR}/.workload_identity.wlconfig
      {
        "type": "external_account",
        "audience": "//iam.googleapis.com/projects/${GC_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL}/providers/${WORKLOAD_IDENTITY_PROVIDER}",
        "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
        "token_url": "https://sts.googleapis.com/v1/token",
        "credential_source": {
          "file": "${CI_BUILDS_DIR}/.workload_identity.jwt"
        },
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SERVICE_ACCOUNT}:generateAccessToken"
      }
      EOF

      export GOOGLE_APPLICATION_CREDENTIALS=${CI_BUILDS_DIR}/.workload_identity.wlconfig
      echo "Authenticated as: ${SERVICE_ACCOUNT}"

terragrunt:fmt:
  stage: checks
  image: alpine/terragrunt:${TG_VERSION}
  script:
    - cd ${TG_STACK_PATH}
    - terragrunt hclfmt --terragrunt-check
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_REF_NAME == $CI_DEFAULT_BRANCH'

terragrunt:plan:
  extends: .gcp-oidc-auth
  stage: plan
  image: alpine/terragrunt:${TG_VERSION}
  script:
    - cd ${TG_STACK_PATH}
    - mkdir -p ${TG_PROVIDER_CACHE_DIR}
    - terragrunt stack run plan --parallelism ${TG_PARALLELISM}
  artifacts:
    paths:
      - ${TG_STACK_PATH}/.terragrunt-stack/**/tfplan
    expire_in: 1 day
  cache:
    key: terragrunt-${CI_COMMIT_REF_SLUG}
    paths:
      - ${TG_PROVIDER_CACHE_DIR}
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_REF_NAME == $CI_DEFAULT_BRANCH'

terragrunt:apply:
  extends: .gcp-oidc-auth
  stage: apply
  image: alpine/terragrunt:${TG_VERSION}
  script:
    - cd ${TG_STACK_PATH}
    - mkdir -p ${TG_PROVIDER_CACHE_DIR}
    - terragrunt stack run apply --parallelism ${TG_PARALLELISM}
  dependencies:
    - terragrunt:plan
  cache:
    key: terragrunt-${CI_COMMIT_REF_SLUG}
    paths:
      - ${TG_PROVIDER_CACHE_DIR}
    policy: pull
  rules:
    - if: '$CI_COMMIT_REF_NAME == $CI_DEFAULT_BRANCH'
      when: manual
  environment:
    name: development
```

---

## Cost Optimization Strategy

### Mock Testing in PRs (Free)

```yaml
# Run mocked tests on every PR
test:mock:
  runs-on: ubuntu-latest
  steps:
    - name: Terraform Test (Mocked)
      run: terraform test
```

```hcl
# tests/main.tftest.hcl - Native mocking
mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = {
      id = "ami-12345678"
    }
  }
}

run "test_instance" {
  command = plan

  assert {
    condition     = aws_instance.web.instance_type == "t3.micro"
    error_message = "Instance type mismatch"
  }
}
```

### Integration Tests on Main (Controlled)

```yaml
# Only run integration tests after merge to main
test:integration:
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - name: Run Terratest
      env:
        AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
        AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      run: |
        cd tests
        go test -v -timeout 30m
```

### Auto-Cleanup for Orphaned Resources

```bash
#!/bin/bash
# scripts/cleanup-test-resources.sh

# Find and delete test resources older than 2 hours
CUTOFF_TIME=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S)

aws resourcegroupstaggingapi get-resources \
  --tag-filters \
    Key=Environment,Values=test \
    Key=ManagedBy,Values=CI \
  --resource-type-filters \
    ec2:instance \
    rds:db \
    s3:bucket \
  --query "ResourceTagMappingList[?Tags[?Key=='CreatedAt' && Value<'${CUTOFF_TIME}']].ResourceARN" \
  --output text | \
  while read -r arn; do
    echo "Deleting resource: $arn"

    # Extract resource type and ID
    resource_type=$(echo "$arn" | cut -d':' -f5 | cut -d'/' -f1)
    resource_id=$(echo "$arn" | cut -d'/' -f2)

    case "$resource_type" in
      instance)
        aws ec2 terminate-instances --instance-ids "$resource_id"
        ;;
      db)
        aws rds delete-db-instance \
          --db-instance-identifier "$resource_id" \
          --skip-final-snapshot
        ;;
      bucket)
        aws s3 rb "s3://$resource_id" --force
        ;;
    esac
  done
```

```yaml
# .github/workflows/cleanup.yml
name: Cleanup Test Resources

on:
  schedule:
    - cron: '0 */2 * * *'  # Every 2 hours
  workflow_dispatch:

jobs:
  cleanup:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111111111111:role/TestResourceCleanup
          aws-region: us-east-1

      - name: Run Cleanup Script
        run: ./scripts/cleanup-test-resources.sh
```

### Resource Tagging for Cost Tracking

```hcl
# Terratest - Tag all test resources
terraformOptions := &terraform.Options{
  TerraformDir: "../examples/complete",
  Vars: map[string]interface{}{
    "tags": map[string]string{
      "Environment": "test",
      "ManagedBy":   "CI",
      "JobID":       os.Getenv("GITHUB_RUN_ID"),
      "CreatedAt":   time.Now().UTC().Format(time.RFC3339),
      "TTL":         "2h",
    },
  },
}

defer terraform.Destroy(t, terraformOptions)
```

```hcl
# Terraform module - Accept and merge tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

locals {
  default_tags = {
    ManagedBy = "Terraform"
    Project   = var.project_name
  }

  merged_tags = merge(local.default_tags, var.tags)
}

resource "aws_instance" "web" {
  # ...
  tags = local.merged_tags
}
```

---

## Security Scanning Integration

### Pre-Commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.88.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_docs
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
      - id: terraform_checkov
        args:
          - --args=--quiet
          - --args=--framework=terraform
      - id: terraform_tfsec
        args:
          - --args=--concise-output
```

### TFSec Configuration

```hcl
# .tfsec/config.yml
minimum_severity: MEDIUM

exclude:
  - aws-s3-enable-versioning  # Handled elsewhere
  - aws-ec2-no-public-egress-sgr  # Intentional

severity_overrides:
  aws-s3-enable-bucket-logging: HIGH
```

### Checkov Integration

```yaml
# checkov job in CI
security:checkov:
  stage: security
  image: bridgecrew/checkov:latest
  script:
    - checkov -d . \
        --framework terraform \
        --output cli \
        --output junitxml \
        --output-file-path checkov-report.xml \
        --skip-check CKV_AWS_18,CKV_AWS_19
  artifacts:
    reports:
      junit: checkov-report.xml
  allow_failure: false
```

### Trivy Config Scanning

```yaml
security:trivy:
  stage: security
  image: aquasec/trivy:latest
  script:
    - trivy config \
        --exit-code 1 \
        --severity HIGH,CRITICAL \
        --format sarif \
        --output trivy-results.sarif \
        ./terraform
  artifacts:
    reports:
      sarif: trivy-results.sarif
```

### Combined Security Workflow

```yaml
# .github/workflows/security.yml
name: Security Scan

on:
  pull_request:
    paths:
      - 'terraform/**'
      - 'infrastructure-live/**'

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run tfsec
        uses: aquasecurity/tfsec-action@v1.0.3
        with:
          soft_fail: false

      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform
          soft_fail: false
          skip_check: CKV_AWS_18,CKV_AWS_19

      - name: Run Trivy
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          scan-ref: '.'
          exit-code: 1
          severity: 'CRITICAL,HIGH'

      - name: Upload SARIF results
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif
```

---

## Atlantis Integration

[Atlantis](https://www.runatlantis.io/) provides Terraform automation via pull request comments.

### atlantis.yaml

```yaml
version: 3
automerge: false
delete_source_branch_on_merge: true

projects:
  - name: vpc
    dir: terraform/modules/vpc
    workspace: default
    terraform_version: v1.9.0
    workflow: standard
    apply_requirements: [approved, mergeable]

  - name: prod-app
    dir: terraform/environments/prod
    workspace: default
    terraform_version: v1.9.0
    workflow: production
    apply_requirements: [approved, mergeable]

workflows:
  standard:
    plan:
      steps:
        - init
        - plan:
            extra_args: ["-lock", "false"]
    apply:
      steps:
        - apply

  production:
    plan:
      steps:
        - init
        - plan:
            extra_args: ["-lock", "false"]
        - run: |
            echo "## Cost Estimate" >> $PLANFILE.md
            infracost breakdown --path . >> $PLANFILE.md
    apply:
      steps:
        - run: echo "Applying to production..."
        - apply
        - run: |
            curl -X POST $SLACK_WEBHOOK \
              -d '{"text":"✅ Production deployment completed"}'
```

### Atlantis Server Configuration

```yaml
# atlantis.yaml (server config)
repos:
  - id: github.com/myorg/infrastructure
    allowed_overrides: [workflow, apply_requirements]
    allow_custom_workflows: true
    pre_workflow_hooks:
      - run: tfsec .
      - run: checkov -d .

workflows:
  default:
    plan:
      steps:
        - env:
            name: AWS_ASSUME_ROLE_ARN
            command: 'echo arn:aws:iam::$AWS_ACCOUNT_ID:role/TerraformCrossAccount'
        - init
        - plan
    apply:
      steps:
        - apply
```

### PR Comment Examples

```bash
# Plan specific project
atlantis plan -p vpc

# Apply specific project
atlantis apply -p vpc

# Plan with custom args
atlantis plan -- -var="instance_count=5"

# Approve changes
atlantis approve_policies -p vpc
```

---

## Best Practices

### 1. Separate Plan and Apply Jobs

```yaml
# ALWAYS separate plan and apply
plan:
  stage: plan
  script:
    - terraform plan -out=tfplan
  artifacts:
    paths: [tfplan]

apply:
  stage: apply
  dependencies: [plan]
  script:
    - terraform apply tfplan
  when: manual
```

### 2. State Locking

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

```yaml
# In CI, use lock timeout
- name: Terraform Apply
  run: terraform apply -lock-timeout=10m tfplan
```

### 3. Approval Gates for Production

```yaml
# GitHub Actions - Use environments
apply:
  environment:
    name: production
    # Requires manual approval configured in repo settings
  when: manual

# GitLab CI - Use manual trigger
apply:
  environment:
    name: production
  when: manual
  only:
    - main
```

### 4. PR Comments with Plan Output

```yaml
- name: Comment PR
  uses: actions/github-script@v7
  if: github.event_name == 'pull_request'
  with:
    script: |
      const output = `#### Terraform Plan 📋
      <details><summary>Show Plan</summary>

      \`\`\`terraform
      ${{ steps.plan.outputs.stdout }}
      \`\`\`

      </details>`;

      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: output
      })
```

### 5. Parallel Execution Control

```yaml
# Terragrunt - Limit parallelism to avoid rate limits
terragrunt stack run apply --parallelism 5

# Terraform - Native parallelism control
terraform apply -parallelism=10 tfplan
```

### 6. Cache Terraform Plugins

```yaml
# GitHub Actions
- name: Cache Terraform Plugins
  uses: actions/cache@v4
  with:
    path: |
      ~/.terraform.d/plugin-cache
      /tmp/provider-cache
    key: ${{ runner.os }}-terraform-${{ hashFiles('**/.terraform.lock.hcl') }}

# GitLab CI
cache:
  key: terraform-${CI_COMMIT_REF_SLUG}
  paths:
    - .terraform
    - /tmp/provider-cache
```

### 7. Resource Tagging

```hcl
# Always tag resources for tracking
locals {
  common_tags = {
    Environment  = var.environment
    ManagedBy    = "Terraform"
    Project      = var.project_name
    CostCenter   = var.cost_center
    Repository   = "github.com/myorg/infrastructure"
    LastModified = timestamp()
  }
}

resource "aws_instance" "web" {
  # ...
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web-${var.environment}"
    Role = "web-server"
  })
}
```

### 8. Drift Detection

```yaml
# .github/workflows/drift-detection.yml
name: Drift Detection

on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM UTC

jobs:
  detect:
    runs-on: ubuntu-latest
    steps:
      - name: Terraform Plan
        run: terraform plan -detailed-exitcode
        continue-on-error: true
        id: plan

      - name: Alert on Drift
        if: steps.plan.outputs.exitcode == 2
        run: |
          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -d '{"text":"🚨 Infrastructure drift detected!"}'
```

### 9. Cost Estimation (Infracost)

```yaml
- name: Setup Infracost
  uses: infracost/actions/setup@v2
  with:
    api-key: ${{ secrets.INFRACOST_API_KEY }}

- name: Generate Cost Estimate
  run: |
    infracost breakdown --path . \
      --format json \
      --out-file /tmp/infracost.json

- name: Post Cost Comment
  uses: infracost/actions/comment@v1
  with:
    path: /tmp/infracost.json
    behavior: update
```

### 10. SSH for Private Repos (Recommended)

```yaml
.ssh-setup:
  before_script:
    - mkdir -p ~/.ssh && chmod 700 ~/.ssh
    - ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
    - ssh-keyscan -t rsa gitlab.com >> ~/.ssh/known_hosts
    # Retrieve SSH key from secret manager
    - echo "$DEPLOY_SSH_KEY" > ~/.ssh/id_rsa
    - chmod 0400 ~/.ssh/id_rsa
```

---

## IAM Configuration for OIDC

### AWS Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:myorg/infrastructure:*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "gitlab.com:aud": "https://gitlab.com"
        },
        "StringLike": {
          "gitlab.com:sub": "project_path:myorg/infrastructure:*"
        }
      }
    }
  ]
}
```

### GCP Workload Identity Setup

```bash
# Create workload identity pool
gcloud iam workload-identity-pools create "gitlab-pool" \
  --location="global" \
  --display-name="GitLab CI Pool"

# Create GitLab provider
gcloud iam workload-identity-pools providers create-oidc "gitlab-provider" \
  --location="global" \
  --workload-identity-pool="gitlab-pool" \
  --issuer-uri="https://gitlab.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.project_path=assertion.project_path"

# Create GitHub provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository"

# Grant service account impersonation
gcloud iam service-accounts add-iam-policy-binding \
  "sa-tf-admin@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/gitlab-pool/attribute.project_path/myorg/infrastructure"
```

---

## References

### Terraform
- [Terraform CI/CD Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/part3.html)
- [GitHub Actions for Terraform](https://learn.hashicorp.com/tutorials/terraform/github-actions)
- [GitLab CI for Terraform](https://docs.gitlab.com/ee/user/infrastructure/iac/)

### Terragrunt
- [Terragrunt Stacks](https://terragrunt.gruntwork.io/docs/features/stacks/)
- [Terragrunt Filters](https://terragrunt.gruntwork.io/docs/features/filter/)
- [Terragrunt CI/CD](https://terragrunt.gruntwork.io/docs/community/ci-cd-integration/)

### Cloud OIDC
- [AWS OIDC for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [GitLab CI with AWS](https://docs.gitlab.com/ci/cloud_services/aws/)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitLab Configure OIDC in GCP](https://gitlab.com/guided-explorations/gcp/configure-openid-connect-in-gcp)

### Security
- [tfsec Documentation](https://aquasecurity.github.io/tfsec/)
- [Checkov Documentation](https://www.checkov.io/)
- [Trivy Config Scanning](https://aquasecurity.github.io/trivy/latest/docs/scanner/misconfiguration/)

### Cost Optimization
- [Infracost Documentation](https://www.infracost.io/docs/)
- [AWS Resource Tagging](https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html)

---

**Back to:** [Main Skill File](../SKILL.md)
