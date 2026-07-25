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

# Subnets must tile the front of the space without gaps or overlaps.
run "private_subnets_are_contiguous_and_disjoint" {
  command = plan

  variables {
    cidr_block = "10.5.0.0/16"
    num_azs    = 3
  }

  assert {
    condition = alltrue([
      for i in range(length(output.computed_private_cidrs) - 1) :
      cidrhost(output.computed_private_cidrs[i + 1], 0) == cidrhost(
        output.computed_private_cidrs[i],
        pow(2, 32 - tonumber(split("/", output.computed_private_cidrs[i])[1]))
      )
    ])
    error_message = "Private subnets are not contiguous: ${jsonencode(output.computed_private_cidrs)}."
  }

  assert {
    condition     = length(distinct(output.computed_private_cidrs)) == length(output.computed_private_cidrs)
    error_message = "Private subnets overlap: ${jsonencode(output.computed_private_cidrs)}."
  }
}
