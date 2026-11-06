locals {
  labels = {
    "app.kubernetes.io/name"       = var.name
    "app.kubernetes.io/managed-by" = "terraform"
  }

  has_secrets      = length(var.secrets) > 0
  k8s_secret_name  = "${var.name}-env"
  secret_store_ref = "${var.name}-aws"
}

################################################################################
# IRSA: one role per workload, trusted only by this service account
################################################################################

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${substr("${var.namespace}-${var.name}", 0, 37)}-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "custom" {
  for_each = var.iam_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

data "aws_iam_policy_document" "secrets" {
  count = local.has_secrets ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.secret_arns
  }
}

resource "aws_iam_role_policy" "secrets" {
  count = local.has_secrets ? 1 : 0

  name   = "external-secrets-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.secrets[0].json
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
    }
  }
}

################################################################################
# External Secrets: Secrets Manager -> Kubernetes Secret -> envFrom
################################################################################

resource "kubectl_manifest" "secret_store" {
  count = local.has_secrets ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata = {
      name      = local.secret_store_ref
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            # ESO requests a token for this service account and assumes its IRSA role.
            jwt = { serviceAccountRef = { name = kubernetes_service_account_v1.this.metadata[0].name } }
          }
        }
      }
    }
  })

  depends_on = [aws_iam_role_policy.secrets]
}

resource "kubectl_manifest" "external_secret" {
  count = local.has_secrets ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      refreshInterval = var.secret_refresh_interval
      secretStoreRef  = { name = local.secret_store_ref, kind = "SecretStore" }
      target          = { name = local.k8s_secret_name, creationPolicy = "Owner" }
      data = [for env_name, s in var.secrets : {
        secretKey = env_name
        remoteRef = merge({ key = s.remote_key }, s.property == null ? {} : { property = s.property })
      }]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

################################################################################
# Deployment and Service
################################################################################

resource "kubernetes_deployment_v1" "this" {
  #checkov:skip=CKV_K8S_11:No CPU limit on purpose. CFS throttling hurts latency under bursts; the CPU request guarantees the pod's share.
  #checkov:skip=CKV_K8S_35:Secrets as env vars is the ADR 4 decision; values are synced by External Secrets and etcd is KMS-encrypted.
  #checkov:skip=CKV_K8S_15:imagePullPolicy Always adds a registry round-trip to every pod start, i.e. to every scale-up. Use immutable tags or digests instead.
  #checkov:skip=CKV_K8S_43:The module deploys whatever image reference it is given; pinning to a digest is the deploy pipeline's job (out of scope).
  wait_for_rollout = var.wait_for_rollout

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { "app.kubernetes.io/name" = var.name }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        service_account_name             = kubernetes_service_account_v1.this.metadata[0].name
        termination_grace_period_seconds = var.termination_grace_period_seconds

        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name    = var.name
          image   = var.image
          command = var.command
          args    = var.args

          dynamic "port" {
            for_each = var.container_port == null ? [] : [var.container_port]
            content {
              name           = "http"
              container_port = port.value
            }
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env_from" {
            for_each = local.has_secrets ? [local.k8s_secret_name] : []
            content {
              secret_ref {
                name = env_from.value
              }
            }
          }

          resources {
            requests = {
              cpu    = var.resources.cpu_request
              memory = var.resources.memory_request
            }
            limits = {
              memory = var.resources.memory_limit
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          dynamic "readiness_probe" {
            for_each = var.container_port == null ? [] : [var.container_port]
            content {
              http_get {
                path = var.health_path
                port = readiness_probe.value
              }
              period_seconds = 10
            }
          }

          dynamic "liveness_probe" {
            for_each = var.container_port == null ? [] : [var.container_port]
            content {
              http_get {
                path = var.health_path
                port = liveness_probe.value
              }
              initial_delay_seconds = 10
              period_seconds        = 20
            }
          }
        }
      }
    }
  }

  lifecycle {
    # HPA/KEDA changes replicas at runtime; Terraform must not reset them on every apply.
    ignore_changes = [spec[0].replicas]
  }

  depends_on = [kubectl_manifest.external_secret, aws_iam_role_policy.custom]
}

resource "kubernetes_service_v1" "this" {
  count = var.container_port == null ? 0 : 1

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    selector = { "app.kubernetes.io/name" = var.name }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}
