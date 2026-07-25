terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # v6 added the per-resource `region` argument this module relies on to
      # build VPCs across regions from a single provider configuration.
      version = ">= 6.0"
    }
  }
}
