# VPC Module - Complete Example
# Demonstrates: for_each loops, conditional resources, locals, dynamic blocks

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local values for computed configurations
locals {
  # Compute availability zones based on subnet configuration
  azs = distinct([for k, v in var.subnets : v.az])

  # Create flat map of all subnets with computed values
  all_subnets = merge(
    { for k, v in var.subnets : k => merge(v, {
      type = "public"
    }) if v.public },
    { for k, v in var.subnets : k => merge(v, {
      type = "private"
    }) if !v.public }
  )

  # Get NAT gateway configuration per AZ
  nat_gateway_azs = var.enable_nat_gateway ? (
    var.single_nat_gateway ? [local.azs[0]] : local.azs
  ) : []

  # Common tags merged with resource-specific tags
  common_tags = merge(
    var.tags,
    {
      Module    = "vpc"
      Terraform = "true"
    }
  )
}

# VPC Resource
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    local.common_tags,
    {
      Name = var.name
    }
  )
}

# Internet Gateway for public subnets
resource "aws_internet_gateway" "main" {
  count = length([for k, v in var.subnets : k if v.public]) > 0 ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-igw"
    }
  )
}

# Subnets - using for_each for flexibility
resource "aws_subnet" "main" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.public

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-${each.key}"
      Type = each.value.public ? "public" : "private"
      AZ   = each.value.az
    },
    lookup(each.value, "tags", {})
  )
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  for_each = toset(local.nat_gateway_azs)

  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-nat-${each.key}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways - one per AZ or single shared
resource "aws_nat_gateway" "main" {
  for_each = toset(local.nat_gateway_azs)

  allocation_id = aws_eip.nat[each.key].id

  # Find first public subnet in this AZ
  subnet_id = [
    for k, v in aws_subnet.main : v.id
    if var.subnets[k].public && var.subnets[k].az == each.key
  ][0]

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-nat-${each.key}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Route table for public subnets
resource "aws_route_table" "public" {
  count = length([for k, v in var.subnets : k if v.public]) > 0 ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-public"
      Type = "public"
    }
  )
}

# Public route to Internet Gateway
resource "aws_route" "public_internet" {
  count = length(aws_route_table.public) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

# Route tables for private subnets - one per NAT gateway
resource "aws_route_table" "private" {
  for_each = toset(local.nat_gateway_azs)

  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-private-${each.key}"
      Type = "private"
      AZ   = each.key
    }
  )
}

# Private routes to NAT Gateway
resource "aws_route" "private_nat" {
  for_each = toset(local.nat_gateway_azs)

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[each.key].id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  for_each = { for k, v in var.subnets : k => v if v.public }

  subnet_id      = aws_subnet.main[each.key].id
  route_table_id = aws_route_table.public[0].id
}

# Associate private subnets with appropriate private route table
resource "aws_route_table_association" "private" {
  for_each = { for k, v in var.subnets : k => v if !v.public }

  subnet_id = aws_subnet.main[each.key].id

  # Use single NAT gateway route table or AZ-specific one
  route_table_id = var.single_nat_gateway ? (
    aws_route_table.private[local.nat_gateway_azs[0]].id
  ) : (
    aws_route_table.private[each.value.az].id
  )
}

# VPC Flow Logs (optional)
resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = var.flow_logs_role_arn
  log_destination = var.flow_logs_destination

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-flow-logs"
    }
  )
}

# VPC Endpoints (optional, example for S3)
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  route_table_ids = concat(
    aws_route_table.public[*].id,
    [for rt in aws_route_table.private : rt.id]
  )

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-s3-endpoint"
    }
  )
}

# Data source for current region
data "aws_region" "current" {}
