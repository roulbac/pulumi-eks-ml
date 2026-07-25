output "node_role_arn" {
  description = "ARN of the role Karpenter-provisioned nodes assume. Referenced by the EC2NodeClass."
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the Karpenter node role."
  value       = aws_iam_role.node.name
}

output "controller_role_arn" {
  description = "ARN of the Karpenter controller role. Annotate the controller's service account with this."
  value       = module.controller_irsa.iam_role_arn
}

output "controller_policy_json" {
  description = "The rendered controller policy. Exposed so tests can assert its statements without applying."
  value       = data.aws_iam_policy_document.controller.json
}
