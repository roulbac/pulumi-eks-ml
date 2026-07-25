locals {
  vpc_prefix = tonumber(split("/", var.cidr_block)[1])

  # Number of /28 blocks the VPC divides into. The public subnet is the last
  # one, leaving the whole front of the address space to private subnets.
  total_28_blocks = pow(2, 28 - local.vpc_prefix)
  public_cidr     = cidrsubnet(var.cidr_block, 28 - local.vpc_prefix, local.total_28_blocks - 1)

  # Pick the largest private subnet size (smallest prefix) that still leaves the
  # trailing /28 free. Because the public block is always the *last* /28, it
  # falls inside the last subnet of any size, so the first num_azs subnets clear
  # it exactly when the split yields more subnets than we need. That single
  # condition subsumes the explicit overlap check in vpc/utils.py.
  feasible_prefixes = [
    for p in range(local.vpc_prefix + 1, 29) : p
    if pow(2, p - local.vpc_prefix) > var.num_azs
  ]
  private_prefix = try(local.feasible_prefixes[0], null)

  private_cidrs = [
    for i in range(var.num_azs) :
    cidrsubnet(var.cidr_block, local.private_prefix - local.vpc_prefix, i)
  ]

  azs = data.aws_availability_zones.this.names

  tags = var.tags
}

data "aws_availability_zones" "this" {
  region = var.region
  state  = "available"
}

resource "aws_vpc" "this" {
  region = var.region

  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, { Name = "${var.name}-vpc" })

  lifecycle {
    precondition {
      condition     = local.private_prefix != null
      error_message = "VPC CIDR ${var.cidr_block} cannot provide ${var.num_azs} private subnets while reserving a /28 public subnet. Use a larger CIDR or fewer AZs."
    }
  }
}

# ---------------------------------------------------------------------------
# Private subnets — one per AZ, sized to consume the front of the address space
# ---------------------------------------------------------------------------

resource "aws_subnet" "private" {
  region = var.region

  count = var.num_azs

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index % length(local.azs)]

  tags = merge(local.tags, { Name = "${var.name}-private-subnet-${count.index + 1}" })
}

# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

resource "aws_route_table" "public" {
  region = var.region

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table" "private" {
  region = var.region

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  region = var.region

  count = var.num_azs

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Internet egress — minimal public subnet fronting a single NAT gateway
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  region = var.region

  count = var.setup_internet_egress ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  region = var.region

  count = var.setup_internet_egress ? 1 : 0

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_cidr
  availability_zone = local.azs[0]

  tags = merge(local.tags, { Name = "${var.name}-public-subnet" })
}

resource "aws_eip" "nat" {
  region = var.region

  count = var.setup_internet_egress ? 1 : 0

  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  region = var.region

  count = var.setup_internet_egress ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.tags, { Name = "${var.name}-nat-gateway" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "public" {
  region = var.region

  count = var.setup_internet_egress ? 1 : 0

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route" "private" {
  region = var.region

  count = var.setup_internet_egress ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  region = var.region

  count = var.setup_internet_egress ? 1 : 0

  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public.id
}
