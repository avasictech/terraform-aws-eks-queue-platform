locals {
  name = var.deployment_name
}

check "replica_bounds" {
  assert {
    condition     = var.min_replicas <= var.max_replicas
    error_message = "min_replicas must be <= max_replicas."
  }
}

################################################################################
# Let KEDA read this queue's depth, and nothing else
################################################################################

data "aws_iam_policy_document" "read_queue_depth" {
  statement {
    actions   = ["sqs:GetQueueAttributes"]
    resources = [var.queue_arn]
  }
}

resource "aws_iam_role_policy" "keda_read_queue" {
  name   = "sqs-depth-${var.namespace}-${local.name}"
  role   = var.keda_operator_role_name
  policy = data.aws_iam_policy_document.read_queue_depth.json
}

################################################################################
# TriggerAuthentication + ScaledObject
################################################################################

resource "kubectl_manifest" "trigger_auth" {
  yaml_body = yamlencode({
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"
    metadata = {
      name      = "${local.name}-sqs"
      namespace = var.namespace
    }
    spec = {
      # Use the KEDA operator's own IRSA role (granted above), not the worker's.
      podIdentity = {
        provider      = "aws"
        identityOwner = "keda"
      }
    }
  })
}

resource "kubectl_manifest" "scaled_object" {
  yaml_body = yamlencode({
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = local.name
      namespace = var.namespace
    }
    spec = merge(
      {
        scaleTargetRef  = { name = var.deployment_name }
        pollingInterval = var.polling_interval
        cooldownPeriod  = var.cooldown_period
        minReplicaCount = var.min_replicas
        maxReplicaCount = var.max_replicas

        advanced = {
          horizontalPodAutoscalerConfig = {
            behavior = {
              scaleUp = {
                stabilizationWindowSeconds = var.scale_up.stabilization_seconds
                selectPolicy               = "Max"
                policies = [
                  { type = "Pods", value = var.scale_up.pods, periodSeconds = var.scale_up.period_seconds },
                  { type = "Percent", value = var.scale_up.percent, periodSeconds = var.scale_up.period_seconds },
                ]
              }
              scaleDown = {
                stabilizationWindowSeconds = var.scale_down.stabilization_seconds
                policies = [
                  { type = "Percent", value = var.scale_down.percent, periodSeconds = var.scale_down.period_seconds },
                ]
              }
            }
          }
        }

        triggers = [{
          type              = "aws-sqs-queue"
          authenticationRef = { name = "${local.name}-sqs" }
          metadata = {
            queueURL              = var.queue_url
            awsRegion             = var.aws_region
            queueLength           = tostring(var.messages_per_pod)
            activationQueueLength = tostring(var.activation_messages)
            scaleOnInFlight       = tostring(var.scale_on_in_flight)
          }
        }]
      },
      var.fallback_replicas == null ? {} : {
        fallback = {
          failureThreshold = 3
          replicas         = var.fallback_replicas
        }
      },
    )
  })

  depends_on = [kubectl_manifest.trigger_auth, aws_iam_role_policy.keda_read_queue]
}
