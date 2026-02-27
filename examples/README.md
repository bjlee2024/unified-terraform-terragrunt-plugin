# Unified Terraform/Terragrunt Skill Examples

This directory contains comprehensive working examples demonstrating best practices from the unified skill.

## Directory Structure

```
examples/
├── terraform/              # Terraform module examples
│   ├── vpc-module/         # Complete VPC module
│   │   ├── main.tf         # Main resources
│   │   ├── variables.tf    # Input variables with validation
│   │   ├── outputs.tf      # Output values
│   │   └── versions.tf     # Version constraints
│   └── tests/              # Terraform tests
│       └── vpc_test.tftest.hcl  # Unit tests with mock providers
│
└── terragrunt/             # Terragrunt examples
    ├── catalog/            # Catalog-based architecture
    │   ├── units/          # Reusable infrastructure units
    │   │   └── s3/         # S3 bucket unit with dependencies
    │   └── stacks/         # Multi-unit compositions
    │       └── frontend/   # Frontend stack (S3, CloudFront, Route53)
    └── live/               # Live environment configuration
        └── root.hcl        # Root configuration with remote state
```

## Terraform Examples

### VPC Module (`terraform/vpc-module/`)

A production-ready VPC module demonstrating:

**Key Features:**
- ✅ **for_each loops** for flexible subnet creation
- ✅ **Conditional resources** (NAT Gateway, Flow Logs)
- ✅ **Local values** for computed configurations
- ✅ **Dynamic blocks** for route tables
- ✅ **Comprehensive validation** on all inputs
- ✅ **Proper tagging** strategy
- ✅ **Multiple AZ support** with single or per-AZ NAT
- ✅ **VPC endpoints** (S3 example)

**Usage:**
```bash
cd terraform/vpc-module

# Initialize
terraform init

# Run tests
terraform test

# Plan with example values
terraform plan -var="name=my-vpc" \
  -var="vpc_cidr=10.0.0.0/16" \
  -var='subnets={"public-a"={cidr="10.0.1.0/24",az="us-east-1a",public=true}}'
```

**Example Configuration:**
```hcl
module "vpc" {
  source = "./vpc-module"

  name     = "production-vpc"
  vpc_cidr = "10.0.0.0/16"

  subnets = {
    public-a = {
      cidr   = "10.0.1.0/24"
      az     = "us-east-1a"
      public = true
    }
    public-b = {
      cidr   = "10.0.2.0/24"
      az     = "us-east-1b"
      public = true
    }
    private-a = {
      cidr   = "10.0.11.0/24"
      az     = "us-east-1a"
      public = false
    }
    private-b = {
      cidr   = "10.0.12.0/24"
      az     = "us-east-1b"
      public = false
    }
  }

  enable_nat_gateway = true
  single_nat_gateway = false  # HA setup
  enable_s3_endpoint = true

  tags = {
    Environment = "production"
    Project     = "myapp"
  }
}
```

### VPC Test Suite (`terraform/tests/vpc_test.tftest.hcl`)

Comprehensive test coverage with 8 test scenarios:

1. **Basic VPC** - Public subnets only
2. **Single NAT Gateway** - Cost-optimized setup
3. **Multiple NAT Gateways** - High availability setup
4. **VPC Flow Logs** - Logging configuration
5. **Tag Validation** - Tagging strategy
6. **Invalid CIDR** - Validation failure test
7. **Flow Logs Validation** - Required parameters test
8. **Output Structure** - Output validation

**Running Tests:**
```bash
cd terraform/vpc-module

# Run all tests
terraform test

# Run specific test
terraform test -filter=basic_vpc_public_only

# Verbose output
terraform test -verbose
```

**Test Features:**
- Mock providers for fast execution (no AWS API calls)
- Multiple assertions per test
- Positive and negative test cases
- Output structure validation

## Terragrunt Examples

### S3 Unit (`terragrunt/catalog/units/s3/`)

A reusable S3 bucket unit demonstrating:

**Key Features:**
- ✅ **Values pattern** for configuration
- ✅ **Dependencies** with mock outputs
- ✅ **Computed values** from parent configs
- ✅ **Encryption** with KMS dependency
- ✅ **Lifecycle rules** configuration
- ✅ **Versioning** and object lock
- ✅ **Replication** configuration
- ✅ **CORS** and website hosting

**Usage:**
```bash
cd terragrunt/catalog/units/s3

# Plan with mocked dependencies
terragrunt plan

# Apply
terragrunt apply
```

**Customization via Values:**
```hcl
unit "s3" {
  source = "../../units/s3"

  values = {
    bucket_name         = "my-custom-bucket"
    versioning_enabled  = true
    block_public_access = true

    lifecycle_rules = [
      {
        id      = "archive-old-versions"
        enabled = true
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER" }
        ]
      }
    ]
  }
}
```

### Frontend Stack (`terragrunt/catalog/stacks/frontend/`)

A complete frontend infrastructure stack with 7 integrated units:

**Components:**
1. **S3 Bucket** - Static asset storage with website hosting
2. **CloudFront** - CDN distribution with custom SSL
3. **ACM Certificate** - SSL/TLS certificate (us-east-1)
4. **Route53 Records** - DNS configuration with aliases
5. **CloudFront OAI** - Origin Access Identity for security
6. **S3 Bucket Policy** - CloudFront access permissions
7. **CloudWatch Alarms** - Monitoring for 4xx/5xx errors

**Stack Features:**
- ✅ **Multi-unit composition** with dependencies
- ✅ **Values passing** between units
- ✅ **Cross-unit references** via outputs
- ✅ **Conditional configuration** per environment
- ✅ **IPv6 support**
- ✅ **SPA support** with error page routing
- ✅ **Monitoring** and alerting

**Usage:**
```bash
cd terragrunt/catalog/stacks/frontend

# Plan entire stack
terragrunt run-all plan

# Apply entire stack with dependencies
terragrunt run-all apply

# Apply specific unit
cd s3_bucket && terragrunt apply
```

**Environment Customization:**
The stack adapts to environment:
- **Production**: Global CDN distribution, monitoring enabled
- **Development**: Regional CDN only, reduced costs

### Root Configuration (`terragrunt/live/root.hcl`)

Complete root configuration demonstrating:

**Key Features:**
- ✅ **Remote state** - S3 backend with DynamoDB locking
- ✅ **Provider generation** - AWS provider with default tags
- ✅ **Catalog configuration** - Unit and stack discovery
- ✅ **Multi-region support** - Including us-east-1 alias
- ✅ **Environment parsing** from directory structure
- ✅ **Common variables** auto-generation
- ✅ **Retry logic** for transient errors
- ✅ **Hooks** for before/after actions
- ✅ **Input defaults** with environment-specific values

**Directory Structure:**
```
live/
├── root.hcl                 # This file
├── dev/
│   ├── us-east-1/
│   │   └── frontend/
│   │       └── terragrunt.hcl
│   └── us-west-2/
│       └── backend/
│           └── terragrunt.hcl
└── prod/
    ├── us-east-1/
    │   └── frontend/
    │       └── terragrunt.hcl
    └── us-west-2/
        └── backend/
            └── terragrunt.hcl
```

**Auto-detected Values:**
- `account_id` from environment name (dev/staging/prod)
- `region` from directory path
- `environment` from directory path
- Common tags applied to all resources

**Usage:**
```bash
# From any child directory
cd live/dev/us-east-1/frontend

# Terragrunt automatically includes root.hcl
terragrunt plan
terragrunt apply

# Multi-environment operations
cd live/dev && terragrunt run-all plan
cd live/prod && terragrunt run-all apply
```

## Best Practices Demonstrated

### Terraform
1. **for_each over count** - More flexible and maintainable
2. **Validation on inputs** - Catch errors early
3. **Proper output structure** - Both maps and lists
4. **Local values** - Computed configurations
5. **Conditional resources** - Feature flags
6. **Comprehensive testing** - Multiple scenarios
7. **Mock providers** - Fast test execution

### Terragrunt
1. **Values pattern** - Configuration injection
2. **Mock outputs** - Plan without dependencies
3. **Unit composition** - Stacks from reusable units
4. **DRY configuration** - No duplication
5. **Remote state isolation** - Per environment/region
6. **Provider generation** - Consistent configuration
7. **Dependency management** - Explicit and implicit

## Common Patterns

### Validation Pattern
```hcl
variable "name" {
  type = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 32
    error_message = "Name must be between 1 and 32 characters"
  }
}
```

### Values Pattern (Terragrunt)
```hcl
# In unit
locals {
  default_values = { /* defaults */ }
  values = merge(local.default_values, try(var.values, {}))
}

# In stack
unit "example" {
  source = "../../units/example"
  values = { /* overrides */ }
}
```

### Dependency Pattern (Terragrunt)
```hcl
dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_id = "mock-key-id"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  kms_key_id = dependency.kms.outputs.key_id
}
```

### Testing Pattern
```hcl
run "test_name" {
  command = plan

  variables = { /* test inputs */ }

  assert {
    condition     = /* assertion */
    error_message = "Descriptive message"
  }
}
```

## Next Steps

1. **Customize** - Adapt examples to your requirements
2. **Test** - Run `terraform test` to validate changes
3. **Extend** - Add more units and stacks
4. **Deploy** - Use Terragrunt run-all for deployments

## Reference

See the main skill documentation:
- `../terraform-best-practices.md` - Terraform guidelines
- `../terragrunt-best-practices.md` - Terragrunt patterns
- `../SKILL.md` - Complete skill reference
