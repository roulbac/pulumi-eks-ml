locals {
  regions = sort(keys(var.vpcs))

  # hub_and_spoke is a strict subset of full_mesh. Both produce unordered pairs;
  # sorting each pair alphabetically keeps resource keys stable so switching
  # topology only adds or removes the difference rather than churning every
  # connection.
  # Both branches are coerced to list(list(string)). The inner tolist matters
  # because a for-expression yields a *tuple*, and a ternary between two tuples
  # demands equal lengths — which these never have. flatten() is not an option
  # either: it recurses, collapsing the pairs into a flat list of strings.
  hub_pairs = tolist([
    for r in local.regions : tolist([var.hub, r]) if r != var.hub
  ])

  # Compared by index rather than by value, since HCL's < is numeric only.
  # local.regions is sorted, so index order is alphabetical order.
  mesh_pairs = tolist([
    for pair in setproduct(local.regions, local.regions) : tolist(pair)
    if index(local.regions, pair[0]) < index(local.regions, pair[1])
  ])

  raw_pairs = var.topology == "hub_and_spoke" ? local.hub_pairs : local.mesh_pairs

  pairs = {
    for p in local.raw_pairs :
    "${sort(p)[0]}-to-${sort(p)[1]}" => {
      region_a = sort(p)[0]
      region_b = sort(p)[1]
    }
  }
}

# ---------------------------------------------------------------------------
# Peering connections
#
# Every resource below carries an explicit `region`, so the whole mesh is built
# from one provider configuration over a dynamic region list. Before AWS
# provider v6 this needed one aliased provider per region, which in turn made
# the region set static.
# ---------------------------------------------------------------------------

resource "aws_vpc_peering_connection" "this" {
  for_each = local.pairs

  region = each.value.region_a

  vpc_id      = var.vpcs[each.value.region_a].vpc_id
  peer_vpc_id = var.vpcs[each.value.region_b].vpc_id
  peer_region = each.value.region_b

  # Cross-region connections cannot self-accept; the accepter below handles it.
  auto_accept = false

  tags = merge(var.tags, { Name = "${var.name}-peering-${each.key}" })
}

resource "aws_vpc_peering_connection_accepter" "this" {
  for_each = local.pairs

  region = each.value.region_b

  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.key].id
  auto_accept               = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  tags = merge(var.tags, { Name = "${var.name}-accepter-${each.key}" })
}

# Requester-side DNS resolution. Split out because the requester options can
# only be set once the connection is active.
resource "aws_vpc_peering_connection_options" "requester" {
  for_each = local.pairs

  region = each.value.region_a

  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.key].id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

# ---------------------------------------------------------------------------
# Routes — both directions, on each VPC's shared private route table
# ---------------------------------------------------------------------------

resource "aws_route" "a_to_b" {
  for_each = local.pairs

  region = each.value.region_a

  route_table_id            = var.vpcs[each.value.region_a].private_route_table_id
  destination_cidr_block    = var.vpcs[each.value.region_b].vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.key].id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

resource "aws_route" "b_to_a" {
  for_each = local.pairs

  region = each.value.region_b

  route_table_id            = var.vpcs[each.value.region_b].private_route_table_id
  destination_cidr_block    = var.vpcs[each.value.region_a].vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.key].id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}
