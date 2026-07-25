output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_id" {
  description = "ID of the minimal /28 public subnet, or null when internet egress is disabled."
  value       = one(aws_subnet.public[*].id)
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, ordered by AZ."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets, ordered by AZ."
  value       = aws_subnet.private[*].cidr_block
}

output "private_route_table_id" {
  description = "ID of the shared private route table. Peering routes attach here."
  value       = aws_route_table.private.id
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway, or null when internet egress is disabled."
  value       = one(aws_nat_gateway.this[*].id)
}

output "region" {
  description = "Region this VPC was created in."
  value       = var.region
}

# Exposed so callers and tests can assert the derived layout without reaching
# into the resources themselves.
output "computed_public_cidr" {
  description = "CIDR the public subnet is (or would be) allocated from."
  value       = local.public_cidr
}

output "computed_private_cidrs" {
  description = "CIDRs allocated to the private subnets."
  value       = local.private_cidrs
}

output "computed_private_prefix" {
  description = "Prefix length chosen for the private subnets."
  value       = local.private_prefix
}
