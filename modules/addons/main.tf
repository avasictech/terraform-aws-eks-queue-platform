locals {
  keda_namespace       = "keda"
  keda_service_account = "keda-operator"
}

################################################################################
# KEDA
#
# The operator gets its own IRSA role with no permissions. Each
# queue-autoscaler module instance attaches a policy for exactly one queue,
# so KEDA can only read the queues it scales on.
################################################################################

data "aws_iam_policy_document" "keda_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${local.keda_namespace}:${local.keda_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "keda_operator" {
  name_prefix        = "${substr(var.cluster_name, 0, 26)}-keda-"
  assume_role_policy = data.aws_iam_policy_document.keda_assume.json
  tags               = var.tags
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_chart_version
  namespace        = local.keda_namespace
  create_namespace = true
  wait             = true

  values = [yamlencode({
    serviceAccount = {
      operator = { name = local.keda_service_account }
    }
    podIdentity = {
      aws = {
        irsa = {
          enabled  = true
          roleArn  = aws_iam_role.keda_operator.arn
          audience = "sts.amazonaws.com"
        }
      }
    }
    # Two replicas of the metrics API server: if it is down, every
    # KEDA-managed HPA loses its metric and freezes at the current size.
    metricsServer = { replicaCount = 2 }
    operator      = { replicaCount = 2 }
  })]
}

################################################################################
# External Secrets Operator
#
# The controller itself has no AWS permissions. Each workload's SecretStore
# authenticates with that workload's own service account token (IRSA), so a
# workload can only read the secrets its own role allows.
################################################################################

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true

  values = [yamlencode({
    installCRDs = true
  })]
}
