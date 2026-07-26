locals {
  # Explicit ingress on the node security group. Kept as data so the rules can
  # be created with for_each and read as a set rather than a wall of resources.
  node_ingress_from_cluster = {
    kubelet     = { port = 10250, description = "Kubelet from the cluster security group" }
    https       = { port = 443, description = "HTTPS from the cluster security group" }
    alb_webhook = { port = 9443, description = "ALB controller webhook from the cluster security group" }
  }

  cluster_from_node = {
    for idx, rule in var.cluster_from_node_sg_rules :
    "${rule.protocol}-${rule.port}" => rule
  }
}

# ---------------------------------------------------------------------------
# Control plane
#
# Fargate + Karpenter only: no managed or self-managed node groups, and no
# module-created security groups. The node security group below is built here
# so the ALB controller's own rule management cannot collide with ours.
# ---------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_private_access = var.endpoint_private_access
  endpoint_public_access  = var.endpoint_public_access

  enabled_log_types   = var.enabled_cluster_log_types
  authentication_mode = "API_AND_CONFIG_MAP"

  # Create the IAM OIDC provider that every IRSA role trusts.
  enable_irsa = true

  # CoreDNS is deliberately excluded here — see aws_eks_addon.coredns below.
  bootstrap_self_managed_addons = false

  addons = {
    kube-proxy = {
      addon_version               = var.kube_proxy_version
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    vpc-cni = {
      addon_version               = var.vpc_cni_version
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  create_security_group      = false
  create_node_security_group = false

  fargate_profiles = {
    system = {
      name       = "${var.name}-fgt-profile"
      subnet_ids = var.subnet_ids
      selectors  = var.fargate_selectors
    }
  }

  tags = var.tags
}

# Read back the EKS-managed primary security group rather than relying on a
# module output name, which has moved between major versions.
data "aws_eks_cluster" "this" {
  region = var.region

  name = module.eks.cluster_name
}

locals {
  cluster_security_group_id = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# ---------------------------------------------------------------------------
# CoreDNS
#
# Installed only once the Fargate profile exists. CoreDNS has no EC2 capacity
# to land on at this point in the bootstrap, so a profile selecting it must be
# in place first or the addon sits degraded. This ordering is the reason
# bootstrap_self_managed_addons is off above.
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "coredns" {
  region = var.region

  cluster_name  = module.eks.cluster_name
  addon_name    = "coredns"
  addon_version = var.coredns_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Node security group
# ---------------------------------------------------------------------------

resource "aws_security_group" "node" {
  region = var.region

  name_prefix = "${var.name}-node-"
  description = "Security group for the EKS nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-node-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "node_self_all" {
  region = var.region

  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
  description                  = "All traffic within the node security group"
}

resource "aws_vpc_security_group_ingress_rule" "node_self_nfs" {
  region = var.region

  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "Allow NFS within node security group"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster" {
  for_each = local.node_ingress_from_cluster

  region = var.region

  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = local.cluster_security_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  description                  = each.value.description
}

resource "aws_vpc_security_group_egress_rule" "node_all" {
  region = var.region

  security_group_id = aws_security_group.node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# Ingress on the cluster security group for traffic originating from nodes.
resource "aws_vpc_security_group_ingress_rule" "cluster_from_node" {
  for_each = local.cluster_from_node

  region = var.region

  security_group_id            = local.cluster_security_group_id
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = each.value.protocol
  description                  = each.value.description
}
