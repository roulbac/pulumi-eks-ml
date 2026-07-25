variable "name" {
  description = "Name prefix for the Karpenter IAM resources."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster Karpenter manages nodes for."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider."
  type        = string
}

variable "oidc_issuer" {
  description = "Cluster OIDC issuer, with or without the https:// scheme."
  type        = string
}

variable "karpenter_namespace" {
  description = "Namespace the Karpenter controller runs in."
  type        = string
  default     = "karpenter"
}

variable "karpenter_service_account" {
  description = "Service account name the Karpenter controller runs as."
  type        = string
  default     = "karpenter"
}

variable "node_policy_arns" {
  description = "Managed policies attached to the Karpenter node role."
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientFullAccess",
  ]
}

variable "region" {
  description = "Region to scope the controller policy and access entry to. Defaults to the provider's region."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the IAM resources."
  type        = map(string)
  default     = {}
}
