variable "name" {
  description = "Name prefix applied to every resource in this VPC."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC. Must be no smaller than a /28."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR, e.g. \"10.0.0.0/16\"."
  }

  validation {
    condition     = tonumber(split("/", var.cidr_block)[1]) <= 28
    error_message = "VPC CIDR ${var.cidr_block} is too small to allocate a /28 public subnet."
  }
}

variable "num_azs" {
  description = "Number of availability zones to spread private subnets across, one subnet per AZ."
  type        = number
  default     = 3

  validation {
    condition     = var.num_azs >= 1
    error_message = "num_azs must be at least 1."
  }
}

variable "setup_internet_egress" {
  description = <<-EOT
    Create the public subnet, internet gateway and NAT gateway so private
    subnets reach the internet. When false the VPC is fully isolated and only
    the private subnets and their route table are created.
  EOT
  type        = bool
  default     = true
}

variable "region" {
  description = <<-EOT
    Region to create this VPC in. Defaults to the provider's region. Set this
    to build VPCs in several regions from a single provider configuration —
    supported natively by AWS provider v6 and up.
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to every resource in this VPC."
  type        = map(string)
  default     = {}
}
