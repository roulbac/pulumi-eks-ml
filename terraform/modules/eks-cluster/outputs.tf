output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint. Feed this to the kubernetes and helm providers in layer 2."
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA bundle for the API server. Required to configure the kubernetes provider."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "EKS-managed primary security group for the control plane."
  value       = local.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group attached to Karpenter-provisioned nodes. Referenced by the EC2NodeClass and by EFS mount targets."
  value       = aws_security_group.node.id
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider. Every IRSA role trusts this."
  value       = module.eks.oidc_provider_arn
}

output "oidc_issuer" {
  description = "Cluster OIDC issuer URL. The irsa module strips the scheme itself."
  value       = module.eks.cluster_oidc_issuer_url
}

output "subnet_ids" {
  description = "Subnets the cluster was built in, passed through for addons and node classes."
  value       = var.subnet_ids
}

output "region" {
  description = "Region the cluster was created in."
  value       = var.region
}
