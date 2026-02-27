# VPC Module Outputs
# Demonstrates: comprehensive outputs with descriptions, structured data

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = aws_vpc.main.arn
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "subnet_ids" {
  description = "Map of subnet names to subnet IDs"
  value       = { for k, v in aws_subnet.main : k => v.id }
}

output "subnet_arns" {
  description = "Map of subnet names to subnet ARNs"
  value       = { for k, v in aws_subnet.main : k => v.arn }
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value = [
    for k, v in aws_subnet.main : v.id
    if var.subnets[k].public
  ]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value = [
    for k, v in aws_subnet.main : v.id
    if !var.subnets[k].public
  ]
}

output "subnet_cidrs" {
  description = "Map of subnet names to CIDR blocks"
  value       = { for k, v in aws_subnet.main : k => v.cidr_block }
}

output "subnet_azs" {
  description = "Map of subnet names to availability zones"
  value       = { for k, v in aws_subnet.main : k => v.availability_zone }
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway (if created)"
  value       = try(aws_internet_gateway.main[0].id, null)
}

output "nat_gateway_ids" {
  description = "Map of availability zones to NAT Gateway IDs"
  value       = { for k, v in aws_nat_gateway.main : k => v.id }
}

output "nat_gateway_public_ips" {
  description = "Map of availability zones to NAT Gateway public IPs"
  value       = { for k, v in aws_eip.nat : k => v.public_ip }
}

output "public_route_table_id" {
  description = "The ID of the public route table (if created)"
  value       = try(aws_route_table.public[0].id, null)
}

output "private_route_table_ids" {
  description = "Map of availability zones to private route table IDs"
  value       = { for k, v in aws_route_table.private : k => v.id }
}

output "s3_endpoint_id" {
  description = "The ID of the S3 VPC endpoint (if created)"
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "flow_log_id" {
  description = "The ID of the VPC Flow Log (if created)"
  value       = try(aws_flow_log.main[0].id, null)
}

output "availability_zones" {
  description = "List of availability zones used by subnets"
  value       = distinct([for k, v in var.subnets : v.az])
}

output "network_summary" {
  description = "Summary of network configuration for reference"
  value = {
    vpc_id             = aws_vpc.main.id
    vpc_cidr           = aws_vpc.main.cidr_block
    availability_zones = distinct([for k, v in var.subnets : v.az])
    public_subnets     = length([for k, v in var.subnets : k if v.public])
    private_subnets    = length([for k, v in var.subnets : k if !v.public])
    nat_gateways       = length(aws_nat_gateway.main)
    has_internet_gateway = length(aws_internet_gateway.main) > 0
  }
}
