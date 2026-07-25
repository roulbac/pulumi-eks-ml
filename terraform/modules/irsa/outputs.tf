output "iam_role_arn" {
  description = "ARN of the created IAM role. Annotate the service account with this."
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "Name of the created IAM role."
  value       = aws_iam_role.this.name
}

output "assume_role_policy_json" {
  description = "The rendered trust policy. Exposed so tests can assert both the sub and aud conditions survive."
  value       = data.aws_iam_policy_document.assume_role.json
}
