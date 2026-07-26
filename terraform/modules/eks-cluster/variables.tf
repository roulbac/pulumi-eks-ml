variable "name" {
  description = "Cluster name, also used as the prefix for the resources around it."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster and its nodes live in."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs, the Fargate profile and Karpenter-provisioned nodes."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane."
  type        = string
  default     = "1.35"
}

variable "region" {
  description = "Region to create the cluster in. Defaults to the provider's region."
  type        = string
  default     = null
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types shipped to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "coredns_version" {
  description = "Version of the CoreDNS managed addon. Null tracks the EKS default for the cluster version."
  type        = string
  default     = null
}

variable "kube_proxy_version" {
  description = "Version of the kube-proxy managed addon. Null tracks the EKS default."
  type        = string
  default     = null
}

variable "vpc_cni_version" {
  description = "Version of the VPC CNI managed addon. Null tracks the EKS default."
  type        = string
  default     = null
}

variable "fargate_selectors" {
  description = <<-EOT
    Pod selectors for the Fargate profile. The defaults keep the cluster
    bootstrappable with no EC2 capacity: CoreDNS must run somewhere for the
    cluster to function, and Karpenter must run somewhere to create the nodes
    everything else lands on.
  EOT
  type = list(object({
    namespace = string
    labels    = optional(map(string))
  }))
  default = [
    {
      namespace = "kube-system"
      labels    = { "eks.amazonaws.com/component" = "coredns" }
    },
    {
      namespace = "karpenter"
      labels    = { "app.kubernetes.io/name" = "karpenter" }
    },
  ]
}

variable "cluster_from_node_sg_rules" {
  description = <<-EOT
    Ingress opened on the cluster security group for traffic from the node
    security group, as (port, protocol, description) triples.
  EOT
  type = list(object({
    port        = number
    protocol    = string
    description = string
  }))
  default = [
    { port = 443, protocol = "tcp", description = "Kubernetes API accessible from node SG" },
    { port = 53, protocol = "udp", description = "CoreDNS accessible from node SG" },
    { port = 53, protocol = "tcp", description = "CoreDNS accessible from node SG" },
    { port = 10250, protocol = "tcp", description = "Kubelet on Fargate nodes accessible from node SG" },
    { port = 9153, protocol = "tcp", description = "Prometheus metrics from Fargate nodes" },
    { port = 8085, protocol = "tcp", description = "Metrics for Karpenter" },
  ]
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint publicly."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Expose the Kubernetes API endpoint inside the VPC."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
