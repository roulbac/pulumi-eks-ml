output "iam_role_arn" {
  description = "ARN of the created IAM role. Annotate the service account with this."
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "Name of the created IAM role."
  value       = aws_iam_role.this.name
}

output "assume_role_policy_json" {
  description = <<-EOT
    The rendered trust policy. Exposed so tests can assert both the sub and aud
    conditions survive. Note this is rendered by the provider, so it is only
    meaningful under a real provider — offline tests with a mocked provider
    should assert on the derived values below instead.
  EOT
  value       = data.aws_iam_policy_document.assume_role.json
}

output "normalized_issuer" {
  description = "The issuer with any https:// scheme stripped, as used in the condition keys."
  value       = local.issuer
}

output "trust_subject" {
  description = "The service-account subject this role trusts."
  value       = local.subject
}

output "subject_condition_test" {
  description = "IAM condition operator applied to the subject: StringLike for wildcard names, StringEquals otherwise."
  value       = local.subject_condition_test
}
