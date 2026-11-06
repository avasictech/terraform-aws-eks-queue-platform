data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first three zones are used (slice below), so new AZs don't change the result.
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project   = var.name
    ManagedBy = "terraform"
  }

  namespace = "jobs"

  # Longest time the worker may spend on one message. Everything else is derived from it.
  max_processing_seconds = 45
}

################################################################################
# Network
################################################################################

module "vpc" {
  #checkov:skip=CKV_TF_1:Registry module pinned to an exact version; commit-hash pinning applies to git sources.
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = "10.40.0.0/16"

  azs             = local.azs
  private_subnets = ["10.40.0.0/19", "10.40.32.0/19", "10.40.64.0/19"]
  public_subnets  = ["10.40.96.0/24", "10.40.97.0/24", "10.40.98.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # demo cost; use one per AZ in production

  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
}

################################################################################
# Cluster and platform add-ons
################################################################################

module "cluster" {
  source = "../../modules/cluster"

  name       = var.name
  subnet_ids = module.vpc.private_subnets

  # Public endpoint so the example can be applied from a laptop, limited to your IP.
  endpoint_public_access = true
  public_access_cidrs    = var.api_allowed_cidrs
}

module "addons" {
  source = "../../modules/addons"

  cluster_name      = module.cluster.cluster_name
  oidc_provider_arn = module.cluster.oidc_provider_arn
  oidc_issuer       = module.cluster.oidc_issuer

  # Add-ons need nodes to run on.
  depends_on = [module.cluster]
}

################################################################################
# Queue, dead-letter queue and a secret for the worker
################################################################################

resource "aws_sqs_queue" "jobs_dlq" {
  name                      = "${var.name}-jobs-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "jobs" {
  name                    = "${var.name}-jobs"
  sqs_managed_sse_enabled = true

  # Must exceed the processing time, or a message becomes visible again and a
  # second pod picks it up while the first is still working on it.
  visibility_timeout_seconds = local.max_processing_seconds * 2
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.jobs_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_secretsmanager_secret" "downstream_api" {
  #checkov:skip=CKV2_AWS_57:A third-party API token is rotated by whoever issues it, not by a Lambda here. Pods pick up a new value on restart (ADR 4).
  #checkov:skip=CKV_AWS_149:The AWS-managed key is enough for a single-account secret; a customer key adds cost and only matters for cross-account access.
  name                    = "${var.name}/worker/downstream-api"
  recovery_window_in_days = 0 # demo only, allows immediate re-create
}

# Demo value so the example works end to end. In a real setup the value is
# written out of band (console/CLI/rotation), so it never lands in Terraform state.
resource "random_password" "downstream_api_token" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "downstream_api" {
  secret_id     = aws_secretsmanager_secret.downstream_api.id
  secret_string = jsonencode({ token = random_password.downstream_api_token.result })
}

resource "kubernetes_namespace_v1" "jobs" {
  metadata {
    name = local.namespace
  }

  depends_on = [module.cluster]
}

################################################################################
# HTTP service: accepts jobs and puts them on the queue
################################################################################

data "aws_iam_policy_document" "api_send" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.jobs.arn]
  }
}

module "api" {
  source = "../../modules/workload"

  name           = "api"
  namespace      = kubernetes_namespace_v1.jobs.metadata[0].name
  image          = var.api_image
  replicas       = 2
  container_port = 8080
  aws_region     = var.region

  env = {
    QUEUE_URL = aws_sqs_queue.jobs.url
  }

  oidc_provider_arn = module.cluster.oidc_provider_arn
  oidc_issuer       = module.cluster.oidc_issuer
  iam_policies      = { "sqs-send" = data.aws_iam_policy_document.api_send.json }

  depends_on = [module.addons]
}

################################################################################
# Queue worker: consumes jobs, scaled by KEDA on queue depth
################################################################################

data "aws_iam_policy_document" "worker_consume" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.jobs.arn]
  }
}

module "worker" {
  source = "../../modules/workload"

  name       = "worker"
  namespace  = kubernetes_namespace_v1.jobs.metadata[0].name
  image      = var.worker_image
  aws_region = var.region

  # On scale-down the pod gets SIGTERM, stops receiving, and finishes the
  # message it holds. Give it the full processing time plus some margin.
  termination_grace_period_seconds = local.max_processing_seconds + 15

  env = {
    QUEUE_URL              = aws_sqs_queue.jobs.url
    MAX_PROCESSING_SECONDS = tostring(local.max_processing_seconds)
  }

  secrets = {
    DOWNSTREAM_API_TOKEN = {
      remote_key = aws_secretsmanager_secret.downstream_api.name
      property   = "token"
    }
  }
  secret_arns = [aws_secretsmanager_secret.downstream_api.arn]

  oidc_provider_arn = module.cluster.oidc_provider_arn
  oidc_issuer       = module.cluster.oidc_issuer
  iam_policies      = { "sqs-consume" = data.aws_iam_policy_document.worker_consume.json }

  depends_on = [module.addons, aws_secretsmanager_secret_version.downstream_api]
}

module "worker_autoscaler" {
  source = "../../modules/queue-autoscaler"

  deployment_name         = module.worker.deployment_name
  namespace               = kubernetes_namespace_v1.jobs.metadata[0].name
  queue_url               = aws_sqs_queue.jobs.url
  queue_arn               = aws_sqs_queue.jobs.arn
  aws_region              = var.region
  keda_operator_role_name = module.addons.keda_operator_role_name

  # One pod handles ~2 msg/s; we want a backlog cleared within ~10 s.
  messages_per_pod = 20
  min_replicas     = 1
  max_replicas     = 20

  depends_on = [module.addons]
}
