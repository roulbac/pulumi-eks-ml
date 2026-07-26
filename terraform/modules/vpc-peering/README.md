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

### Known MiniStack gap

MiniStack does not implement the `ModifyVpcPeeringConnectionOptions` EC2
action, so `enable_remote_dns_resolution` is set to `false` in the integration
suite. Everything else applies for real — the peering connections themselves
and both directions of routing. Production callers leave the flag at its
default of `true`.

Cross-VPC DNS resolution is therefore the one behaviour here the emulator
cannot cover; it needs a real apply of `examples/multi-region` to verify.
