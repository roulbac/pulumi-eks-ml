# Real apply against MiniStack. Ports tests/integration/test_eks.py.
#
# Run with:
#   terraform test -test-directory=tests-integration

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

variables {
  oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/INTEGRATION"
  oidc_issuer       = "oidc.eks.us-east-1.amazonaws.com/id/INTEGRATION"
}

run "creates_role_with_wildcard_subject" {
  command = apply

  variables {
    role_name          = "tf-it-external-dns"
    trust_sa_namespace = "kube-system"
    trust_sa_name      = "external-dns*"
  }

  assert {
    condition     = output.iam_role_name == "tf-it-external-dns"
    error_message = "Role name did not round-trip: ${output.iam_role_name}."
  }

  assert {
    condition     = strcontains(output.iam_role_arn, ":role/tf-it-external-dns")
    error_message = "Unexpected role ARN: ${output.iam_role_arn}."
  }

  assert {
    condition     = strcontains(output.assume_role_policy_json, "StringLike")
    error_message = "Wildcard service account must produce a StringLike subject condition."
  }
}

run "creates_role_with_attached_policies" {
  command = apply

  variables {
    role_name            = "tf-it-attached"
    trust_sa_namespace   = "kube-system"
    trust_sa_name        = "efs-csi-controller-sa"
    attached_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"]
  }

  # Both restrictions must be present on a real, applied role — this is the
  # trust-policy bug the Python implementation still has.
  assert {
    condition = strcontains(
      output.assume_role_policy_json,
      "system:serviceaccount:kube-system:efs-csi-controller-sa"
    )
    error_message = "Applied role lost its :sub restriction."
  }

  assert {
    condition     = strcontains(output.assume_role_policy_json, "sts.amazonaws.com")
    error_message = "Applied role lost its :aud restriction."
  }
}
