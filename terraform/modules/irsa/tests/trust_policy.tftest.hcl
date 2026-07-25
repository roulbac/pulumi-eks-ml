# Guards the IRSA trust policy, including the sub/aud condition collision that
# the Python implementation still carries. Plan-only, runs offline.

mock_provider "aws" {}

variables {
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
  oidc_issuer       = "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
}

run "exact_service_account_restricts_both_sub_and_aud" {
  command = plan

  variables {
    role_name          = "test-exact"
    trust_sa_namespace = "kube-system"
    trust_sa_name      = "efs-csi-controller-sa"
  }

  # The regression this exists for: the subject condition must survive
  # alongside the audience condition.
  assert {
    condition = strcontains(
      output.assume_role_policy_json,
      "system:serviceaccount:kube-system:efs-csi-controller-sa"
    )
    error_message = "Trust policy lost its :sub restriction — the role would be assumable by any service account in the cluster."
  }

  assert {
    condition     = strcontains(output.assume_role_policy_json, "sts.amazonaws.com")
    error_message = "Trust policy is missing the :aud restriction."
  }

  assert {
    condition     = strcontains(output.assume_role_policy_json, "StringEquals")
    error_message = "An exact service-account name must use StringEquals."
  }

  assert {
    condition     = !strcontains(output.assume_role_policy_json, "StringLike")
    error_message = "An exact service-account name must not use StringLike."
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
    condition     = strcontains(output.assume_role_policy_json, "StringLike")
    error_message = "A wildcard service-account name must use StringLike for the :sub condition."
  }

  assert {
    condition     = strcontains(output.assume_role_policy_json, "system:serviceaccount:skypilot:*")
    error_message = "Wildcard subject was not rendered correctly."
  }

  assert {
    condition     = strcontains(output.assume_role_policy_json, "sts.amazonaws.com")
    error_message = "Trust policy is missing the :aud restriction."
  }
}

run "issuer_url_scheme_is_stripped" {
  command = plan

  variables {
    role_name          = "test-scheme"
    oidc_issuer        = "https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE"
    trust_sa_namespace = "karpenter"
    trust_sa_name      = "karpenter"
  }

  # aws_eks_cluster reports the issuer with a scheme; IAM condition keys must
  # not carry one.
  assert {
    condition     = !strcontains(output.assume_role_policy_json, "https://oidc.eks")
    error_message = "Condition keys must use the bare issuer host+path, not the full URL."
  }

  assert {
    condition     = strcontains(output.assume_role_policy_json, "oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE:sub")
    error_message = "Subject condition key was not built from the stripped issuer."
  }
}
