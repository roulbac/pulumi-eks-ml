variable "role_name" {
  description = "Name of the IAM role to create."
  type        = string
}

variable "description" {
  description = "Description applied to the IAM role."
  type        = string
  default     = "IAM role for a Kubernetes service account (IRSA)."
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider."
  type        = string
}

variable "oidc_issuer" {
  description = "Cluster OIDC issuer, with or without the https:// scheme."
  type        = string
}

variable "trust_sa_namespace" {
  description = "Namespace of the service account allowed to assume this role."
  type        = string
}

variable "trust_sa_name" {
  description = <<-EOT
    Name of the service account allowed to assume this role. A "*" anywhere in
    the value switches the subject condition from StringEquals to StringLike.
  EOT
  type        = string
}

variable "inline_policies" {
  description = "Inline policies to embed in the role, keyed by policy name with a JSON document as the value."
  type        = map(string)
  default     = {}
}

variable "attached_policy_arns" {
  description = "ARNs of managed policies to attach to the role."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the IAM role."
  type        = map(string)
  default     = {}
}
