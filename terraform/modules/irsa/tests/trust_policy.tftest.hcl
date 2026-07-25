# Offline checks on the values that feed the trust policy.
#
# The policy JSON itself is rendered by the AWS provider, so under a mocked
# provider it is a placeholder rather than a real document. The assertions on
# the rendered JSON — including the sub/aud regression — live in
# tests-integration/, which runs against MiniStack with a real provider.

mock_provider "aws" {}

variables {
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
  oidc_issuer       = "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
}

run "exact_service_account_uses_string_equals" {
  command = plan

  variables {
    role_name          = "test-exact"
    trust_sa_namespace = "kube-system"
    trust_sa_name      = "efs-csi-controller-sa"
  }

  assert {
    condition     = output.subject_condition_test == "StringEquals"
    error_message = "An exact service-account name must use StringEquals, got ${output.subject_condition_test}."
  }

  assert {
    condition     = output.trust_subject == "system:serviceaccount:kube-system:efs-csi-controller-sa"
    error_message = "Unexpected trust subject: ${output.trust_subject}."
  }
}

run "wildcard_service_account_uses_string_like" {
  command = plan

  variables {
    role_name          = "test-wildcard"
    trust_sa_namespace = "skypilot"
    trust_sa_name      = "*"
  }

  assert {
    condition     = output.subject_condition_test == "StringLike"
    error_message = "A wildcard service-account name must use StringLike, got ${output.subject_condition_test}."
  }

  assert {
    condition     = output.trust_subject == "system:serviceaccount:skypilot:*"
    error_message = "Unexpected wildcard subject: ${output.trust_subject}."
  }
}

run "partial_wildcard_also_uses_string_like" {
  command = plan

  variables {
    role_name          = "test-partial-wildcard"
    trust_sa_namespace = "kube-system"
    trust_sa_name      = "external-dns*"
  }

  assert {
    condition     = output.subject_condition_test == "StringLike"
    error_message = "A partially wildcarded name must use StringLike, got ${output.subject_condition_test}."
  }
}

# aws_eks_cluster reports the issuer with a scheme; IAM condition keys must not
# carry one.
run "issuer_url_scheme_is_stripped" {
  command = plan

  variables {
    role_name          = "test-scheme"
    oidc_issuer        = "https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
    trust_sa_namespace = "karpenter"
    trust_sa_name      = "karpenter"
  }

  assert {
    condition     = output.normalized_issuer == "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
    error_message = "Issuer scheme was not stripped: ${output.normalized_issuer}."
  }
}

run "bare_issuer_is_left_alone" {
  command = plan

  variables {
    role_name          = "test-bare"
    trust_sa_namespace = "karpenter"
    trust_sa_name      = "karpenter"
  }

  assert {
    condition     = output.normalized_issuer == "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
    error_message = "A bare issuer should pass through unchanged: ${output.normalized_issuer}."
  }
}
