# Real apply against MiniStack. Ports tests/integration/test_vpc.py.
#
# Requires a running MiniStack (terraform/test/ministack.sh up) and
# AWS_ENDPOINT_URL pointing at it. The AWS provider honours AWS_ENDPOINT_URL
# for every service, so no per-service endpoints block is needed.
#
# Run with:
#   terraform test -test-directory=tests-integration

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

variables {
  name = "tf-it"
}

run "creates_the_expected_subnet_layout" {
  command = apply

  variables {
    cidr_block            = "10.42.0.0/16"
    num_azs               = 3
    setup_internet_egress = true
  }

  # The exact CIDR set asserted by the Pulumi integration test.
  assert {
    condition = toset(output.private_subnet_cidrs) == toset([
      "10.42.0.0/18", "10.42.64.0/18", "10.42.128.0/18"
    ])
    error_message = "Unexpected private subnet CIDRs: ${jsonencode(output.private_subnet_cidrs)}."
  }

  assert {
    condition     = length(output.private_subnet_ids) == 3
    error_message = "Expected 3 private subnets, got ${length(output.private_subnet_ids)}."
  }

  assert {
    condition     = output.public_subnet_id != null
    error_message = "Public subnet should exist when internet egress is enabled."
  }

  assert {
    condition     = output.nat_gateway_id != null
    error_message = "NAT gateway should exist when internet egress is enabled."
  }

  assert {
    condition     = output.vpc_cidr_block == "10.42.0.0/16"
    error_message = "VPC CIDR did not round-trip: ${output.vpc_cidr_block}."
  }
}

run "isolated_vpc_has_no_egress_resources" {
  command = apply

  variables {
    name                  = "tf-it-isolated"
    cidr_block            = "10.43.0.0/16"
    num_azs               = 2
    setup_internet_egress = false
  }

  assert {
    condition     = output.public_subnet_id == null
    error_message = "No public subnet should be created when egress is disabled."
  }

  assert {
    condition     = output.nat_gateway_id == null
    error_message = "No NAT gateway should be created when egress is disabled."
  }

  # The private route table still exists so peering routes have somewhere to go.
  assert {
    condition     = output.private_route_table_id != null
    error_message = "Private route table must exist even without internet egress."
  }
}
