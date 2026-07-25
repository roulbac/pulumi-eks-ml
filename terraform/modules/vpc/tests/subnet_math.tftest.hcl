# Ports the subnet allocation cases from tests/unit/test_vpc.py to native
# Terraform tests. Everything here is plan-only against a mocked AWS provider,
# so the suite runs offline with no credentials.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-west-2a", "us-west-2b", "us-west-2c"]
    }
  }
}

variables {
  name = "test"
}

# /16 with 3 AZs is the shape every reference project uses: three maximised
# /18s at the front, the public /28 pinned to the very end.
run "slash16_three_azs" {
  command = plan

  variables {
    cidr_block = "10.42.0.0/16"
    num_azs    = 3
  }

  assert {
    condition     = output.computed_private_prefix == 18
    error_message = "Expected /18 private subnets, got /${output.computed_private_prefix}."
  }

  assert {
    condition = output.computed_private_cidrs == [
      "10.42.0.0/18", "10.42.64.0/18", "10.42.128.0/18"
    ]
    error_message = "Private CIDRs did not match the expected maximised layout: ${jsonencode(output.computed_private_cidrs)}."
  }

  assert {
    condition     = output.computed_public_cidr == "10.42.255.240/28"
    error_message = "Public subnet must be the final /28, got ${output.computed_public_cidr}."
  }
}

run "slash16_one_az" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/16"
    num_azs    = 1
  }

  # One AZ still needs a split into two, so the trailing /28 stays clear.
  assert {
    condition     = output.computed_private_prefix == 17
    error_message = "Expected a /17 for a single AZ, got /${output.computed_private_prefix}."
  }

  assert {
    condition     = output.computed_private_cidrs == ["10.0.0.0/17"]
    error_message = "Unexpected single-AZ layout: ${jsonencode(output.computed_private_cidrs)}."
  }
}

run "slash16_four_azs" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/16"
    num_azs    = 4
  }

  # Four subnets need a split into eight, since four /18s would swallow the
  # trailing /28.
  assert {
    condition     = output.computed_private_prefix == 19
    error_message = "Expected /19 private subnets for 4 AZs, got /${output.computed_private_prefix}."
  }

  assert {
    condition = output.computed_private_cidrs == [
      "10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19", "10.0.96.0/19"
    ]
    error_message = "Unexpected four-AZ layout: ${jsonencode(output.computed_private_cidrs)}."
  }
}

run "slash20_three_azs" {
  command = plan

  variables {
    cidr_block = "10.1.0.0/20"
    num_azs    = 3
  }

  assert {
    condition     = output.computed_private_prefix == 22
    error_message = "Expected /22 private subnets, got /${output.computed_private_prefix}."
  }

  assert {
    condition     = output.computed_public_cidr == "10.1.15.240/28"
    error_message = "Public subnet must be the final /28 of the /20, got ${output.computed_public_cidr}."
  }
}

# The tightest CIDR that still works: a /26 splits into four /28s, so three AZs
# fit ahead of the reserved public block.
run "smallest_viable_cidr" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/26"
    num_azs    = 3
  }

  assert {
    condition     = output.computed_private_prefix == 28
    error_message = "Expected /28 private subnets at the boundary, got /${output.computed_private_prefix}."
  }

  assert {
    condition = output.computed_private_cidrs == [
      "10.0.0.0/28", "10.0.0.16/28", "10.0.0.32/28"
    ]
    error_message = "Unexpected boundary layout: ${jsonencode(output.computed_private_cidrs)}."
  }

  assert {
    condition     = output.computed_public_cidr == "10.0.0.48/28"
    error_message = "Public subnet must be the final /28, got ${output.computed_public_cidr}."
  }
}

# The invariant vpc/utils.py enforces with an explicit overlap check: private
# subnets live inside the VPC and never swallow the reserved public /28.
run "private_subnets_never_swallow_the_public_block" {
  command = plan

  variables {
    cidr_block = "10.5.0.0/16"
    num_azs    = 3
  }

  # Terraform has no cidrcontains, so the invariant is stated as address
  # arithmetic: the private subnets together must end before the final 16
  # addresses that the public /28 occupies.
  assert {
    condition = (
      var.num_azs * pow(2, 32 - output.computed_private_prefix)
      <= pow(2, 32 - tonumber(split("/", var.cidr_block)[1])) - 16
    )
    error_message = "Private subnets run into the reserved public /28: ${jsonencode(output.computed_private_cidrs)} vs ${output.computed_public_cidr}."
  }

  assert {
    condition     = length(distinct(output.computed_private_cidrs)) == length(output.computed_private_cidrs)
    error_message = "Private subnets overlap each other: ${jsonencode(output.computed_private_cidrs)}."
  }
}

# Same invariant at the tightest CIDR, where the public block sits immediately
# after the last private subnet.
run "boundary_case_keeps_the_public_block_clear" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/26"
    num_azs    = 3
  }

  # At the /26 boundary the fit is exact: three /28s consume 48 of the 64
  # addresses, leaving precisely the 16 the public block needs.
  assert {
    condition = (
      var.num_azs * pow(2, 32 - output.computed_private_prefix)
      == pow(2, 32 - tonumber(split("/", var.cidr_block)[1])) - 16
    )
    error_message = "Boundary case should consume the address space exactly: ${jsonencode(output.computed_private_cidrs)} vs ${output.computed_public_cidr}."
  }
}
