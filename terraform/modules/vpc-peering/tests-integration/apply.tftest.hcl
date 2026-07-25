# Real apply against MiniStack. Ports tests/integration/test_vpc_peering.py.
#
# Builds three VPCs in three regions from the sibling vpc module, peers them
# hub-and-spoke, then asserts the mesh shape. Exercises MiniStack's per-region
# isolation (available since v1.4.0) as well as the peering resources.
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
  name = "tf-it-peering"
}

run "vpc_us_east_1" {
  command = apply

  module {
    # Relative to the module root being tested, not to this test file.
    source = "../vpc"
  }

  variables {
    name                  = "tf-it-use1"
    cidr_block            = "10.1.0.0/16"
    region                = "us-east-1"
    num_azs               = 2
    setup_internet_egress = false
  }
}

run "vpc_us_west_2" {
  command = apply

  module {
    # Relative to the module root being tested, not to this test file.
    source = "../vpc"
  }

  variables {
    name                  = "tf-it-usw2"
    cidr_block            = "10.11.0.0/16"
    region                = "us-west-2"
    num_azs               = 2
    setup_internet_egress = false
  }
}

run "vpc_eu_west_1" {
  command = apply

  module {
    # Relative to the module root being tested, not to this test file.
    source = "../vpc"
  }

  variables {
    name                  = "tf-it-euw1"
    cidr_block            = "10.20.0.0/16"
    region                = "eu-west-1"
    num_azs               = 2
    setup_internet_egress = false
  }
}

run "hub_and_spoke_mesh" {
  command = apply

  variables {
    topology = "hub_and_spoke"
    hub      = "us-east-1"

    # MiniStack's EC2 emulation has no ModifyVpcPeeringConnectionOptions
    # action. The connections and routes below still apply for real; only the
    # cross-VPC DNS option is unavailable, so it is disabled here. Production
    # callers leave it at its default of true.
    enable_remote_dns_resolution = false

    vpcs = {
      "us-east-1" = {
        vpc_id                 = run.vpc_us_east_1.vpc_id
        vpc_cidr_block         = run.vpc_us_east_1.vpc_cidr_block
        private_route_table_id = run.vpc_us_east_1.private_route_table_id
      }
      "us-west-2" = {
        vpc_id                 = run.vpc_us_west_2.vpc_id
        vpc_cidr_block         = run.vpc_us_west_2.vpc_cidr_block
        private_route_table_id = run.vpc_us_west_2.private_route_table_id
      }
      "eu-west-1" = {
        vpc_id                 = run.vpc_eu_west_1.vpc_id
        vpc_cidr_block         = run.vpc_eu_west_1.vpc_cidr_block
        private_route_table_id = run.vpc_eu_west_1.private_route_table_id
      }
    }
  }

  assert {
    condition     = length(output.peering_connection_ids) == 2
    error_message = "Hub-and-spoke over 3 regions must create 2 connections, got ${length(output.peering_connection_ids)}."
  }

  assert {
    condition     = !contains(keys(output.peering_connection_ids), "eu-west-1-to-us-west-2")
    error_message = "Spokes must not be peered directly with each other."
  }

  assert {
    condition = alltrue([
      for id in values(output.peering_connection_ids) : startswith(id, "pcx-")
    ])
    error_message = "Peering connections were not created: ${jsonencode(output.peering_connection_ids)}."
  }
}
