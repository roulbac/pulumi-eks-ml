# Asserts the pair-generation logic for both topologies, mirroring the
# expectations in tests/integration/test_vpc_peering.py. Plan-only, offline.

mock_provider "aws" {}

variables {
  name = "test"
  vpcs = {
    "us-east-1" = {
      vpc_id                 = "vpc-aaa"
      vpc_cidr_block         = "10.1.0.0/16"
      private_route_table_id = "rtb-aaa"
    }
    "us-west-2" = {
      vpc_id                 = "vpc-bbb"
      vpc_cidr_block         = "10.11.0.0/16"
      private_route_table_id = "rtb-bbb"
    }
    "eu-west-1" = {
      vpc_id                 = "vpc-ccc"
      vpc_cidr_block         = "10.20.0.0/16"
      private_route_table_id = "rtb-ccc"
    }
  }
}

run "full_mesh_connects_every_pair" {
  command = plan

  variables {
    topology = "full_mesh"
    hub      = null
  }

  # Three regions choose 2 == three connections.
  assert {
    condition     = length(output.peered_region_pairs) == 3
    error_message = "Full mesh over 3 regions must produce 3 pairs, got ${length(output.peered_region_pairs)}."
  }

  assert {
    condition = toset(keys(output.peered_region_pairs)) == toset([
      "eu-west-1-to-us-east-1",
      "eu-west-1-to-us-west-2",
      "us-east-1-to-us-west-2",
    ])
    error_message = "Unexpected full-mesh pairs: ${jsonencode(keys(output.peered_region_pairs))}."
  }
}

run "hub_and_spoke_connects_only_the_hub" {
  command = plan

  variables {
    topology = "hub_and_spoke"
    hub      = "us-east-1"
  }

  assert {
    condition     = length(output.peered_region_pairs) == 2
    error_message = "Hub-and-spoke over 3 regions must produce 2 pairs, got ${length(output.peered_region_pairs)}."
  }

  # Crucially, the two spokes must not be peered with each other.
  assert {
    condition     = !contains(keys(output.peered_region_pairs), "eu-west-1-to-us-west-2")
    error_message = "Hub-and-spoke must not create a spoke-to-spoke connection."
  }

  assert {
    condition = alltrue([
      for p in values(output.peered_region_pairs) :
      p.region_a == "us-east-1" || p.region_b == "us-east-1"
    ])
    error_message = "Every hub-and-spoke pair must include the hub region."
  }
}

# Pair keys are alphabetically ordered so a topology change adds or removes only
# the differing connections instead of recreating all of them.
run "pair_ordering_is_alphabetical" {
  command = plan

  variables {
    topology = "full_mesh"
    hub      = null
  }

  # sort() rather than <, which HCL only defines for numbers.
  assert {
    condition = alltrue([
      for p in values(output.peered_region_pairs) :
      p.region_a == sort([p.region_a, p.region_b])[0]
    ])
    error_message = "Each pair must be stored with region_a alphabetically before region_b."
  }
}
