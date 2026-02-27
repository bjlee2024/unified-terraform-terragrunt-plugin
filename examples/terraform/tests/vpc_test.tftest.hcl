# VPC Module Test Suite
# Demonstrates: unit testing with mock providers, multiple test scenarios

# Mock provider for faster testing without AWS API calls
mock_provider "aws" {
  # Mock data sources
  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
}

# Test 1: Basic VPC with public subnets only
run "basic_vpc_public_only" {
  command = plan

  variables {
    name     = "test-vpc"
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
    }
    enable_nat_gateway = false
    enable_flow_logs   = false
  }

  # Assertions
  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR should be 10.0.0.0/16"
  }

  assert {
    condition     = length(aws_subnet.main) == 2
    error_message = "Should create exactly 2 subnets"
  }

  assert {
    condition     = length(aws_internet_gateway.main) == 1
    error_message = "Should create Internet Gateway for public subnets"
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 0
    error_message = "Should not create NAT Gateway when disabled"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_hostnames == true
    error_message = "DNS hostnames should be enabled by default"
  }
}

# Test 2: VPC with public and private subnets, single NAT gateway
run "vpc_with_single_nat" {
  command = plan

  variables {
    name     = "test-vpc-nat"
    vpc_cidr = "10.1.0.0/16"
    subnets = {
      public-a = {
        cidr   = "10.1.1.0/24"
        az     = "us-east-1a"
        public = true
      }
      public-b = {
        cidr   = "10.1.2.0/24"
        az     = "us-east-1b"
        public = true
      }
      private-a = {
        cidr   = "10.1.11.0/24"
        az     = "us-east-1a"
        public = false
      }
      private-b = {
        cidr   = "10.1.12.0/24"
        az     = "us-east-1b"
        public = false
      }
    }
    enable_nat_gateway  = true
    single_nat_gateway  = true
    enable_s3_endpoint  = true
    enable_flow_logs    = false
  }

  assert {
    condition     = length(aws_subnet.main) == 4
    error_message = "Should create 4 subnets (2 public, 2 private)"
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 1
    error_message = "Should create single NAT Gateway"
  }

  assert {
    condition     = length(aws_eip.nat) == 1
    error_message = "Should create single Elastic IP for NAT Gateway"
  }

  assert {
    condition     = length(output.public_subnet_ids) == 2
    error_message = "Should output 2 public subnet IDs"
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "Should output 2 private subnet IDs"
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1
    error_message = "Should create S3 VPC endpoint when enabled"
  }
}

# Test 3: VPC with multiple NAT gateways (HA setup)
run "vpc_with_multiple_nat" {
  command = plan

  variables {
    name     = "test-vpc-ha"
    vpc_cidr = "10.2.0.0/16"
    subnets = {
      public-a = {
        cidr   = "10.2.1.0/24"
        az     = "us-east-1a"
        public = true
      }
      public-b = {
        cidr   = "10.2.2.0/24"
        az     = "us-east-1b"
        public = true
      }
      private-a = {
        cidr   = "10.2.11.0/24"
        az     = "us-east-1a"
        public = false
      }
      private-b = {
        cidr   = "10.2.12.0/24"
        az     = "us-east-1b"
        public = false
      }
    }
    enable_nat_gateway = true
    single_nat_gateway = false
    enable_flow_logs   = false
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 2
    error_message = "Should create NAT Gateway per AZ for HA"
  }

  assert {
    condition     = length(aws_eip.nat) == 2
    error_message = "Should create Elastic IP per NAT Gateway"
  }

  assert {
    condition     = length(aws_route_table.private) == 2
    error_message = "Should create private route table per AZ"
  }

  assert {
    condition     = length(output.availability_zones) == 2
    error_message = "Should span 2 availability zones"
  }
}

# Test 4: VPC with Flow Logs enabled
run "vpc_with_flow_logs" {
  command = plan

  variables {
    name     = "test-vpc-logs"
    vpc_cidr = "10.3.0.0/16"
    subnets = {
      public-a = {
        cidr   = "10.3.1.0/24"
        az     = "us-east-1a"
        public = true
      }
    }
    enable_nat_gateway     = false
    enable_flow_logs       = true
    flow_logs_role_arn     = "arn:aws:iam::123456789012:role/flow-logs-role"
    flow_logs_destination  = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc/flow-logs"
  }

  assert {
    condition     = length(aws_flow_log.main) == 1
    error_message = "Should create VPC Flow Log when enabled"
  }

  assert {
    condition     = aws_flow_log.main[0].traffic_type == "ALL"
    error_message = "Flow logs should capture ALL traffic"
  }
}

# Test 5: Tag validation
run "vpc_with_tags" {
  command = plan

  variables {
    name     = "test-vpc-tags"
    vpc_cidr = "10.4.0.0/16"
    subnets = {
      public-a = {
        cidr   = "10.4.1.0/24"
        az     = "us-east-1a"
        public = true
        tags = {
          Custom = "subnet-tag"
        }
      }
    }
    tags = {
      Environment = "test"
      Project     = "example"
    }
    enable_nat_gateway = false
    enable_flow_logs   = false
  }

  assert {
    condition     = aws_vpc.main.tags["Environment"] == "test"
    error_message = "VPC should have Environment tag"
  }

  assert {
    condition     = aws_vpc.main.tags["Module"] == "vpc"
    error_message = "VPC should have Module tag from locals"
  }

  assert {
    condition     = aws_subnet.main["public-a"].tags["Custom"] == "subnet-tag"
    error_message = "Subnet should have custom tag"
  }
}

# Test 6: Validation - invalid CIDR should fail
run "invalid_vpc_cidr" {
  command = plan

  variables {
    name     = "test-vpc"
    vpc_cidr = "invalid-cidr"
    subnets = {
      public-a = {
        cidr   = "10.0.1.0/24"
        az     = "us-east-1a"
        public = true
      }
    }
  }

  expect_failures = [
    var.vpc_cidr,
  ]
}

# Test 7: Validation - flow logs require role ARN
run "flow_logs_missing_role" {
  command = plan

  variables {
    name             = "test-vpc"
    vpc_cidr         = "10.5.0.0/16"
    subnets = {
      public-a = {
        cidr   = "10.5.1.0/24"
        az     = "us-east-1a"
        public = true
      }
    }
    enable_flow_logs = true
    # Missing flow_logs_role_arn
  }

  expect_failures = [
    var.flow_logs_role_arn,
  ]
}

# Test 8: Output structure validation
run "verify_outputs" {
  command = plan

  variables {
    name     = "test-vpc-outputs"
    vpc_cidr = "10.6.0.0/16"
    subnets = {
      public-a = {
        cidr   = "10.6.1.0/24"
        az     = "us-east-1a"
        public = true
      }
      private-a = {
        cidr   = "10.6.11.0/24"
        az     = "us-east-1a"
        public = false
      }
    }
    enable_nat_gateway = true
    single_nat_gateway = true
    enable_flow_logs   = false
  }

  assert {
    condition     = output.network_summary.public_subnets == 1
    error_message = "Network summary should show 1 public subnet"
  }

  assert {
    condition     = output.network_summary.private_subnets == 1
    error_message = "Network summary should show 1 private subnet"
  }

  assert {
    condition     = output.network_summary.nat_gateways == 1
    error_message = "Network summary should show 1 NAT gateway"
  }

  assert {
    condition     = output.network_summary.has_internet_gateway == true
    error_message = "Network summary should show Internet Gateway exists"
  }
}
