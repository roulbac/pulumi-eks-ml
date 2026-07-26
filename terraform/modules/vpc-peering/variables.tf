variable "name" {
  description = "Name prefix applied to peering resources."
  type        = string
}

variable "vpcs" {
  description = <<-EOT
    VPCs to peer, keyed by region. Each value carries the attributes the mesh
    needs: the VPC id, its CIDR (used as the route destination from the other
    side) and the private route table that peering routes attach to.
  EOT
  type = map(object({
    vpc_id                 = string
    vpc_cidr_block         = string
    private_route_table_id = string
  }))

  validation {
    condition     = length(var.vpcs) >= 2
    error_message = "At least two VPCs are required to build a peering mesh."
  }
}

variable "topology" {
  description = <<-EOT
    "full_mesh" peers every region with every other region.
    "hub_and_spoke" peers only the hub with each spoke — no spoke-to-spoke path.
  EOT
  type        = string

  validation {
    condition     = contains(["full_mesh", "hub_and_spoke"], var.topology)
    error_message = "topology must be either \"full_mesh\" or \"hub_and_spoke\"."
  }
}

variable "hub" {
  description = "Hub region. Required for hub_and_spoke, must be null for full_mesh."
  type        = string
  default     = null

  validation {
    condition     = !(var.topology == "hub_and_spoke" && var.hub == null)
    error_message = "The hub_and_spoke topology requires a hub region."
  }

  validation {
    condition     = !(var.topology == "full_mesh" && var.hub != null)
    error_message = "The full_mesh topology must not be given a hub region."
  }

  validation {
    condition     = var.hub == null || contains(keys(var.vpcs), coalesce(var.hub, "_"))
    error_message = "The hub region must be present in the vpcs map."
  }
}

variable "enable_remote_dns_resolution" {
  description = <<-EOT
    Resolve the peer VPC's private DNS names across the connection, on both the
    requester and accepter sides. Matches the Pulumi behaviour and should stay
    on against real AWS.

    Turn it off when running against a local AWS emulator. MiniStack does not
    implement the ModifyVpcPeeringConnectionOptions EC2 action, so the peering
    connections and their routes apply cleanly but setting these options fails.
  EOT
  type        = bool
  default     = true
}

variable "create_routes" {
  description = <<-EOT
    Create the two routes per pair that send each VPC's private subnets to the
    other over the peering connection. Leave this on for the normal case.

    Turn it off when routing is managed elsewhere — for example a transit
    gateway owning the route tables — or when running against MiniStack, whose
    CreateRoute cannot resolve a route table that lives in another region.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to peering resources."
  type        = map(string)
  default     = {}
}
