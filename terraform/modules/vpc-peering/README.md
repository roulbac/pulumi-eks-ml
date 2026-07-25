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

Unit tests (`tests/`) cover the pair-generation logic offline against a mocked
provider — pair counts per topology, the absence of spoke-to-spoke links, and
key ordering.

There is deliberately **no MiniStack integration suite for this module.** The
emulator's EC2 surface does not implement `ModifyVpcPeeringConnectionOptions`,
and its peering teardown is incomplete, so a real apply cannot round-trip.
LocalStack has the same gap. What the emulator *can* do — create the VPCs and
the peering connections themselves — was verified during development, but a
suite that cannot destroy what it creates is not worth keeping green.

Peering is therefore covered by the unit tests plus a real apply of
`examples/multi-region` against AWS.

## Emulator-facing flag

`enable_remote_dns_resolution` (default `true`) exists partly for this reason.
Leave it on for real AWS; turn it off if you ever point this module at an
emulator that supports the rest of peering but not the options call.
