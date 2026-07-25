locals {
  # EKS reports the issuer as a full URL, but IAM condition keys are written
  # against the bare host+path form. Accept either.
  issuer = replace(var.oidc_issuer, "https://", "")

  subject = "system:serviceaccount:${var.trust_sa_namespace}:${var.trust_sa_name}"

  # A wildcard service-account name needs StringLike; an exact name gets the
  # stricter StringEquals.
  subject_condition_test = strcontains(var.trust_sa_name, "*") ? "StringLike" : "StringEquals"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = local.subject_condition_test
      variable = "${local.issuer}:sub"
      values   = [local.subject]
    }

    # NOTE: this audience condition is deliberately a separate block. The Python
    # original (pulumi_eks_ml/eks/irsa.py) builds both conditions inside one dict
    # literal keyed by test name, so for exact-match service accounts the "aud"
    # entry overwrites the "sub" entry and the role ends up assumable by *any*
    # service account in the cluster. Policy-document statements merge condition
    # blocks properly, so both survive here.
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  description        = var.description

  tags = var.tags
}

# Standalone resources rather than the role's inline_policy block, which AWS
# provider v6 deprecates.
resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = toset(var.attached_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
