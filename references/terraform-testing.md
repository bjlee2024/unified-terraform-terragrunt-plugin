# Terraform Testing Reference

Complete guide to native Terraform testing using `.tftest.hcl` files (Terraform 1.6+).

---

## Table of Contents

1. [Test File Syntax](#test-file-syntax)
2. [Mock Providers](#mock-providers)
3. [Test Organization](#test-organization)
4. [Common Test Patterns](#common-test-patterns)
5. [Parallel Execution](#parallel-execution)
6. [CI/CD Integration](#cicd-integration)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Test File Syntax

### File Structure

```hcl
# File-level variables (optional)
variables {
  name_prefix = "test"
  environment = "dev"
}

# File-level providers (optional)
provider "aws" {
  region = "us-west-2"
}

# Test run blocks
run "test_name" {
  # Test configuration
}
```

### Test Block Attributes

```hcl
run "descriptive_test_name" {
  # REQUIRED: Test command (plan or apply)
  command = plan  # or apply

  # OPTIONAL: Plan configuration
  plan_options {
    mode    = normal    # normal or refresh-only
    refresh = true      # Enable refresh during plan (default: true)
    replace = [         # Force replacement of specific resources
      aws_instance.example
    ]
    target = [          # Target specific resources
      aws_instance.example
    ]
  }

  # OPTIONAL: Run-block variables (override file-level)
  variables {
    instance_type = "t3.small"
    environment   = "test"
  }

  # OPTIONAL: Assertions
  assert {
    condition     = output.instance_id != ""
    error_message = "Instance ID must not be empty"
  }

  # OPTIONAL: Expected failures (negative testing)
  expect_failures = [
    var.invalid_input
  ]

  # OPTIONAL: Module path (for testing submodules)
  module {
    source = "./modules/vpc"
  }

  # OPTIONAL: State key for parallel execution (Terraform 1.9+)
  state_key = "unique_state_identifier"

  # OPTIONAL: Parallel execution control (Terraform 1.9+)
  parallel = true  # Allow parallel execution (default: true)
}
```

### Plan Options Detail

```hcl
plan_options {
  # Mode: How to execute the plan
  mode = normal           # normal: standard plan
                         # refresh-only: only update state, no changes

  # Refresh: Update state from real infrastructure
  refresh = true         # true (default) or false

  # Replace: Force replacement of resources
  replace = [
    aws_instance.web,
    aws_db_instance.primary
  ]

  # Target: Limit operations to specific resources
  target = [
    module.networking,
    aws_security_group.allow_tls
  ]
}
```

### Assert Block Syntax

```hcl
assert {
  # REQUIRED: Boolean condition to evaluate
  condition = length(output.vpc_id) > 0

  # REQUIRED: Error message if condition fails
  error_message = "VPC ID must be set"
}

# Multiple assertions in one run block
run "validate_outputs" {
  command = plan

  assert {
    condition     = output.vpc_id != ""
    error_message = "VPC ID is required"
  }

  assert {
    condition     = output.subnet_count == 3
    error_message = "Expected 3 subnets, got ${output.subnet_count}"
  }

  assert {
    condition     = can(regex("^vpc-", output.vpc_id))
    error_message = "VPC ID must start with 'vpc-'"
  }
}
```

### Variables Block

```hcl
# FILE-LEVEL VARIABLES: Apply to all run blocks unless overridden
variables {
  region      = "us-west-2"
  environment = "test"
  common_tags = {
    ManagedBy = "Terraform"
    Testing   = "true"
  }
}

# RUN-BLOCK VARIABLES: Override file-level for specific test
run "test_production_config" {
  command = plan

  variables {
    environment = "prod"  # Overrides file-level "test"
    instance_type = "t3.large"
  }

  assert {
    condition     = var.environment == "prod"
    error_message = "Must use production environment"
  }
}
```

---

## Mock Providers

**Available since Terraform 1.7** - Simulate provider behavior without real infrastructure.

### Mock Provider Block

```hcl
mock_provider "aws" {
  # Mock specific resources
  mock_resource "aws_instance" {
    defaults = {
      id  = "i-mock123456"
      ami = "ami-mock"
      arn = "arn:aws:ec2:us-west-2:123456789012:instance/i-mock123456"
    }
  }

  # Mock data sources
  mock_data "aws_ami" {
    defaults = {
      id           = "ami-mock123"
      architecture = "x86_64"
    }
  }
}
```

### Complete Mock Provider Example

```hcl
# tests/vpc_unit_test.tftest.hcl
mock_provider "aws" {
  # Mock VPC resource
  mock_resource "aws_vpc" {
    defaults = {
      id         = "vpc-mock12345"
      cidr_block = "10.0.0.0/16"
      arn        = "arn:aws:ec2:us-west-2:123456789012:vpc/vpc-mock12345"
    }
  }

  # Mock subnet resource with dynamic values
  mock_resource "aws_subnet" {
    defaults = {
      id               = "subnet-mock${each.key}"
      vpc_id           = "vpc-mock12345"
      availability_zone = "us-west-2a"
      cidr_block       = each.value.cidr_block
      arn              = "arn:aws:ec2:us-west-2:123456789012:subnet/subnet-mock${each.key}"
    }
  }

  # Mock availability zones data source
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-west-2a", "us-west-2b", "us-west-2c"]
    }
  }
}

run "validate_vpc_structure" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/16"
  }

  assert {
    condition     = output.vpc_id == "vpc-mock12345"
    error_message = "VPC ID mismatch"
  }
}
```

### Mock Provider Limitations

**When to use mocks:**
- Unit testing module logic without cloud costs
- Testing validation rules and variable constraints
- Testing output calculations
- Rapid feedback during development

**When NOT to use mocks:**
- Integration testing (use real providers)
- Testing actual resource creation behavior
- Verifying provider-specific features
- End-to-end validation

**Limitations:**
- Cannot simulate API errors or rate limits
- No actual state management
- Provider-specific validation not tested
- Resource interdependencies may not behave realistically

---

## Test Organization

### Directory Structure

```
terraform-project/
├── main.tf
├── variables.tf
├── outputs.tf
├── tests/
│   ├── main_unit_test.tftest.hcl          # Unit tests (plan mode)
│   ├── main_integration_test.tftest.hcl   # Integration tests (apply mode)
│   ├── validation_test.tftest.hcl
│   └── edge_cases_test.tftest.hcl
└── modules/
    └── vpc/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── tests/
            ├── vpc_unit_test.tftest.hcl
            └── vpc_integration_test.tftest.hcl
```

### File Naming Conventions

| Pattern | Purpose | Command Mode |
|---------|---------|--------------|
| `*_unit_test.tftest.hcl` | Fast, plan-only tests with mocks | `plan` |
| `*_integration_test.tftest.hcl` | Real infrastructure tests | `apply` |
| `*_validation_test.tftest.hcl` | Input validation tests | `plan` |
| `*_e2e_test.tftest.hcl` | End-to-end workflow tests | `apply` |

### Unit Tests vs Integration Tests

**Unit Tests (`command = plan`)**
```hcl
# tests/vpc_unit_test.tftest.hcl
mock_provider "aws" {
  # Mock configuration
}

run "validate_subnet_count" {
  command = plan  # Fast, no real resources

  variables {
    subnet_count = 3
  }

  assert {
    condition     = length(output.subnet_ids) == 3
    error_message = "Expected 3 subnets"
  }
}
```

**Integration Tests (`command = apply`)**
```hcl
# tests/vpc_integration_test.tftest.hcl
provider "aws" {
  region = "us-west-2"
}

run "create_vpc" {
  command = apply  # Creates real resources

  variables {
    vpc_cidr = "10.0.0.0/16"
  }

  assert {
    condition     = output.vpc_id != ""
    error_message = "VPC was not created"
  }
}

run "verify_subnets" {
  command = apply

  assert {
    condition     = length(output.subnet_ids) > 0
    error_message = "No subnets created"
  }
}
```

---

## Common Test Patterns

### Pattern 1: Testing Module Outputs

```hcl
run "validate_required_outputs" {
  command = plan

  # Verify all required outputs are present
  assert {
    condition     = output.vpc_id != null
    error_message = "vpc_id output is required"
  }

  assert {
    condition     = output.subnet_ids != null
    error_message = "subnet_ids output is required"
  }

  # Verify output types
  assert {
    condition     = can(tolist(output.subnet_ids))
    error_message = "subnet_ids must be a list"
  }
}
```

### Pattern 2: Testing Resource Counts

```hcl
run "test_subnet_count" {
  command = plan

  variables {
    availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
  }

  assert {
    condition     = length(output.subnet_ids) == 3
    error_message = "Expected 3 subnets, got ${length(output.subnet_ids)}"
  }
}

run "test_conditional_resource" {
  command = plan

  variables {
    create_nat_gateway = false
  }

  # Verify resource is not created
  assert {
    condition     = output.nat_gateway_id == null
    error_message = "NAT gateway should not be created when disabled"
  }
}
```

### Pattern 3: Testing Conditional Resources

```hcl
run "nat_gateway_enabled" {
  command = plan

  variables {
    enable_nat_gateway = true
  }

  assert {
    condition     = output.nat_gateway_id != null
    error_message = "NAT gateway should exist when enabled"
  }
}

run "nat_gateway_disabled" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = output.nat_gateway_id == null
    error_message = "NAT gateway should not exist when disabled"
  }
}
```

### Pattern 4: Testing Tags

```hcl
run "verify_resource_tags" {
  command = plan

  variables {
    common_tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = contains(keys(output.vpc_tags), "Environment")
    error_message = "Environment tag is required"
  }

  assert {
    condition     = output.vpc_tags["Environment"] == "test"
    error_message = "Environment tag must be 'test'"
  }
}
```

### Pattern 5: Sequential Tests with Dependencies

```hcl
# First test creates base infrastructure
run "setup_vpc" {
  command = apply

  variables {
    vpc_cidr = "10.0.0.0/16"
  }
}

# Second test uses outputs from first test
run "verify_subnets" {
  command = apply

  variables {
    vpc_id = run.setup_vpc.vpc_id  # Reference previous run
  }

  assert {
    condition     = length(output.subnet_ids) > 0
    error_message = "Subnets should be created in VPC"
  }
}

# Third test builds on previous tests
run "verify_routing" {
  command = apply

  assert {
    condition     = output.route_table_id != ""
    error_message = "Route table should be associated with subnets"
  }
}
```

### Pattern 6: Testing Validation Rules

```hcl
run "test_invalid_cidr" {
  command = plan

  variables {
    vpc_cidr = "invalid"
  }

  # Expect validation to fail
  expect_failures = [
    var.vpc_cidr
  ]
}

run "test_invalid_subnet_count" {
  command = plan

  variables {
    subnet_count = -1
  }

  expect_failures = [
    var.subnet_count
  ]
}
```

### Pattern 7: Testing Data Sources

```hcl
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-west-2a", "us-west-2b"]
    }
  }
}

run "test_az_selection" {
  command = plan

  assert {
    condition     = length(output.selected_azs) == 2
    error_message = "Should select 2 availability zones"
  }

  assert {
    condition     = contains(output.selected_azs, "us-west-2a")
    error_message = "Should include us-west-2a"
  }
}
```

---

## Parallel Execution

**Available since Terraform 1.9** - Run independent tests concurrently for faster feedback.

### Requirements for Parallel Execution

1. **Unique state keys**: Each parallel run needs a unique state identifier
2. **No dependencies**: Tests cannot reference each other's outputs
3. **Isolation**: Tests must not conflict (same resources, shared state)

### State Key Management

```hcl
# PARALLEL: Tests run concurrently
run "test_vpc_1" {
  command   = apply
  state_key = "vpc_1"  # Unique state key
  parallel  = true     # Enable parallel execution (default)

  variables {
    vpc_cidr = "10.0.0.0/16"
  }
}

run "test_vpc_2" {
  command   = apply
  state_key = "vpc_2"  # Different state key
  parallel  = true

  variables {
    vpc_cidr = "10.1.0.0/16"
  }
}

# SEQUENTIAL: Tests run in order (has dependency)
run "setup_network" {
  command   = apply
  state_key = "network"
  parallel  = false  # Force sequential execution
}

run "deploy_app" {
  command   = apply
  state_key = "app"

  variables {
    vpc_id = run.setup_network.vpc_id  # Depends on previous test
  }
}
```

### Example: Mixed Parallel and Sequential

```hcl
# Unit tests: All run in parallel (fast)
run "validate_vpc_cidr" {
  command   = plan
  state_key = "unit_vpc"

  assert {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Invalid CIDR block"
  }
}

run "validate_tags" {
  command   = plan
  state_key = "unit_tags"

  assert {
    condition     = length(var.common_tags) > 0
    error_message = "Tags required"
  }
}

# Integration tests: Sequential (shared resources)
run "create_vpc" {
  command   = apply
  state_key = "int_vpc"
  parallel  = false
}

run "create_subnets" {
  command   = apply
  state_key = "int_subnets"

  variables {
    vpc_id = run.create_vpc.vpc_id
  }
}
```

---

## CI/CD Integration

### GitHub Actions

```yaml
name: Terraform Tests

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  terraform-test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.0

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-west-2

      - name: Terraform Init
        run: terraform init

      - name: Run Unit Tests (Fast)
        run: terraform test -filter=tests/*_unit_test.tftest.hcl

      - name: Run Integration Tests (Slow)
        if: github.event_name == 'push'
        run: terraform test -filter=tests/*_integration_test.tftest.hcl

      - name: Cleanup
        if: always()
        run: terraform test -cleanup
```

### GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - test

terraform-test:
  stage: test
  image: hashicorp/terraform:1.9

  before_script:
    - terraform init

  script:
    # Run unit tests (fast)
    - terraform test -filter=tests/*_unit_test.tftest.hcl

    # Run integration tests only on main branch
    - |
      if [ "$CI_COMMIT_BRANCH" == "main" ]; then
        terraform test -filter=tests/*_integration_test.tftest.hcl
      fi

  after_script:
    - terraform test -cleanup

  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'
```

---

## Best Practices

### 1. **Use Descriptive Test Names**
```hcl
# GOOD: Clear intent
run "validate_vpc_has_dns_support" {
  command = plan
  # ...
}

# BAD: Vague name
run "test1" {
  command = plan
  # ...
}
```

### 2. **Test One Concept Per Run Block**
```hcl
# GOOD: Focused test
run "validate_subnet_count" {
  command = plan

  assert {
    condition     = length(output.subnet_ids) == 3
    error_message = "Expected 3 subnets"
  }
}

# BAD: Testing multiple unrelated things
run "validate_everything" {
  command = plan

  assert { condition = length(output.subnet_ids) == 3 }
  assert { condition = output.vpc_cidr == "10.0.0.0/16" }
  assert { condition = output.enable_dns == true }
  # Too much in one test
}
```

### 3. **Use Mocks for Unit Tests, Real Providers for Integration**
```hcl
# tests/unit_test.tftest.hcl - Fast, no costs
mock_provider "aws" { }

run "unit_test" {
  command = plan
}

# tests/integration_test.tftest.hcl - Slower, validates real behavior
provider "aws" {
  region = "us-west-2"
}

run "integration_test" {
  command = apply
}
```

### 4. **Always Include Error Messages**
```hcl
# GOOD: Helpful error message
assert {
  condition     = output.vpc_id != ""
  error_message = "VPC ID must be set. Check if aws_vpc resource is created."
}

# BAD: No context
assert {
  condition = output.vpc_id != ""
}
```

### 5. **Test Validation Rules Explicitly**
```hcl
run "test_cidr_validation" {
  command = plan

  variables {
    vpc_cidr = "invalid"
  }

  expect_failures = [var.vpc_cidr]
}
```

### 6. **Use File-Level Variables for Common Values**
```hcl
variables {
  region      = "us-west-2"
  environment = "test"
  owner       = "terraform-test"
}

run "test1" {
  # Inherits region, environment, owner
}

run "test2" {
  variables {
    environment = "prod"  # Override only what's different
  }
}
```

### 7. **Organize Tests by Speed (Fast First)**
```
tests/
├── unit/                    # Fast tests (plan mode, mocks)
│   ├── validation_test.tftest.hcl
│   └── logic_test.tftest.hcl
└── integration/             # Slow tests (apply mode, real resources)
    ├── vpc_test.tftest.hcl
    └── e2e_test.tftest.hcl
```

### 8. **Use Regex for String Pattern Validation**
```hcl
assert {
  condition     = can(regex("^vpc-[a-z0-9]+$", output.vpc_id))
  error_message = "VPC ID must match pattern 'vpc-xxxxxxxxx'"
}

assert {
  condition     = can(regex("^arn:aws:", output.vpc_arn))
  error_message = "VPC ARN must be a valid AWS ARN"
}
```

### 9. **Test Edge Cases and Boundaries**
```hcl
run "test_minimum_subnets" {
  variables { subnet_count = 1 }
  # Test lower boundary
}

run "test_maximum_subnets" {
  variables { subnet_count = 16 }
  # Test upper boundary
}

run "test_empty_tags" {
  variables { common_tags = {} }
  # Test empty input
}
```

### 10. **Clean Up Resources After Integration Tests**
```bash
# Automatic cleanup in CI/CD
terraform test -cleanup

# Manual cleanup if needed
cd tests && terraform destroy -auto-approve
```

### 11. **Version Pin in Test Configurations**
```hcl
# tests/versions.tf
terraform {
  required_version = "~> 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### 12. **Document Complex Assertions**
```hcl
run "validate_multi_az_deployment" {
  command = plan

  # Verify subnets are spread across at least 2 AZs
  # This ensures high availability requirements are met
  assert {
    condition     = length(distinct([for s in output.subnets : s.availability_zone])) >= 2
    error_message = "Subnets must span at least 2 availability zones for HA"
  }
}
```

---

## Troubleshooting

### Common Issues

#### 1. **Test fails with "no configuration files"**
```bash
# Error: No configuration files found

# Solution: Ensure test file is in tests/ directory or specify path
terraform test tests/my_test.tftest.hcl
```

#### 2. **Mock provider not working**
```hcl
# Error: Mock provider not recognized

# Solution: Verify Terraform version (1.7+)
terraform version  # Must be >= 1.7.0
```

#### 3. **State conflicts in parallel tests**
```bash
# Error: Resource already exists in state

# Solution: Use unique state keys
run "test1" {
  state_key = "unique_key_1"
}
```

#### 4. **Assertion failures are not clear**
```hcl
# BEFORE: Unclear error
assert {
  condition = length(output.subnets) == 3
}

# AFTER: Clear error message
assert {
  condition     = length(output.subnets) == 3
  error_message = "Expected 3 subnets, got ${length(output.subnets)}. Check subnet_count variable."
}
```

#### 5. **Integration tests time out**
```yaml
# GitHub Actions: Increase timeout
jobs:
  test:
    timeout-minutes: 30  # Default is 10
```

#### 6. **Cannot reference previous run outputs**
```hcl
# Error: run.setup_vpc.vpc_id is null

# Solution: Ensure previous run uses apply, not plan
run "setup_vpc" {
  command = apply  # Must be apply to create resources
}

run "use_vpc" {
  variables {
    vpc_id = run.setup_vpc.vpc_id  # Now available
  }
}
```

### Debugging Tests

```bash
# Run specific test file
terraform test tests/vpc_test.tftest.hcl

# Run tests matching pattern
terraform test -filter=tests/*_unit_test.tftest.hcl

# Run with verbose output
TF_LOG=DEBUG terraform test

# Run single test run block
terraform test -filter=tests/vpc_test.tftest.hcl -var="run_specific_test=true"

# Clean up test resources
terraform test -cleanup
```

### Test Performance Optimization

```bash
# Fast feedback: Run unit tests first
terraform test -filter=tests/*_unit_test.tftest.hcl

# Parallel execution (Terraform 1.9+)
terraform test -parallelism=10

# Skip long-running integration tests locally
terraform test -filter='!tests/*_integration_test.tftest.hcl'
```

---

## Additional Resources

- [Terraform Testing Documentation](https://developer.hashicorp.com/terraform/language/tests)
- [Mock Providers Guide](https://developer.hashicorp.com/terraform/language/tests/mocking)
- [Terraform 1.9 Release Notes](https://github.com/hashicorp/terraform/releases/tag/v1.9.0) (Parallel execution)

---

**Last Updated**: 2025-02-05
**Terraform Version**: 1.9.0+
