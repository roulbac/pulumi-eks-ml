# vpc-peering

Connects a set of VPCs in either a full mesh or a hub-and-spoke topology.

Ported from `pulumi_eks_ml/vpc/multi_region.py`.

## Dynamic regions without provider aliases

Every resource carries an explicit `region`, a per-resource argument added in
AWS provider v6. That is what lets the whole mesh be built from a single
provider configuration over a region list supplied at runtime. Before v6 this
needed one aliased provider per region, and because Terraform cannot
`for_each` over providers, the supported region set would have had to be
hardcoded in the module.

## Topologies

`hub_and_spoke` is a strict subset of `full_mesh`. Pair keys are built from
alphabetically sorted region names (`eu-west-1-to-us-east-1`), so switching
topology adds or removes only the differing connections instead of recreating
all of them.

## Testing

Both suites run against MiniStack only; no other emulator is used anywhere in
this repository's Terraform tests.

- `tests/` — offline, mocked provider. Pair counts per topology, the absence of
  spoke-to-spoke links, and key ordering.
- `tests-integration/` — real applies against MiniStack. Builds three VPCs in
  three regions from the sibling `vpc` module, then peers them hub-and-spoke,
  which also exercises MiniStack's per-region isolation.

### Known MiniStack gaps

Two specific EC2 actions are missing. Both are narrow — peering itself works,
and the emulator creates the VPCs, route tables and peering connections
correctly.

| Gap | Effect | Flag used in the suite |
|---|---|---|
| No `ModifyVpcPeeringConnectionOptions` action | Cross-VPC DNS resolution cannot be set | `enable_remote_dns_resolution = false` |
| `CreateRoute` cannot resolve a route table in another region | Cross-region routes fail with `InvalidRouteTableID.NotFound`, despite the route table existing | `create_routes = false` |

Both flags default to `true` and should stay that way for real AWS. They are
genuine knobs, not test scaffolding — `create_routes` is also what you want
when a transit gateway owns the route tables.

So the integration suite covers pair generation, the cross-region connections
and the accepter handshake. Cross-VPC DNS and the peering routes need a real
apply of `examples/multi-region` to verify.
