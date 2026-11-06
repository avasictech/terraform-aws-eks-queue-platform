variable "name" {
  description = "Name of the Deployment, ServiceAccount, Service and IAM role suffix."
  type        = string
}

variable "namespace" {
  description = "Existing namespace."
  type        = string
}

variable "image" {
  type = string
}

variable "command" {
  type    = list(string)
  default = null
}

variable "args" {
  type    = list(string)
  default = null
}

variable "replicas" {
  description = "Initial replica count. Ignored after creation, because an autoscaler (HPA or KEDA) owns it."
  type        = number
  default     = 1
}

variable "container_port" {
  description = "If set, the container exposes this port and a ClusterIP Service is created."
  type        = number
  default     = null
}

variable "health_path" {
  description = "HTTP readiness/liveness path, used only when container_port is set."
  type        = string
  default     = "/healthz"
}

variable "env" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "resources" {
  type = object({
    cpu_request    = string
    memory_request = string
    memory_limit   = string
  })
  default = {
    cpu_request    = "100m"
    memory_request = "128Mi"
    memory_limit   = "256Mi"
  }
}

variable "termination_grace_period_seconds" {
  description = "For queue workers, set this above the longest message processing time so a scale-down lets in-flight work finish."
  type        = number
  default     = 30
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_issuer" {
  type = string
}

variable "iam_policies" {
  description = "Inline IAM policies (name => JSON) for the workload's IRSA role. Keys must be static strings."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = <<-EOT
    Environment variables loaded from AWS Secrets Manager through External Secrets.
    Map of ENV_VAR_NAME => { remote_key = secret name or ARN, property = optional JSON key }.
  EOT
  type = map(object({
    remote_key = string
    property   = optional(string)
  }))
  default = {}
}

variable "secret_arns" {
  description = "ARNs of the Secrets Manager secrets listed in `secrets`; the IRSA role gets read access to exactly these."
  type        = list(string)
  default     = []
}

variable "secret_refresh_interval" {
  type    = string
  default = "1h"
}

variable "aws_region" {
  type = string
}

variable "wait_for_rollout" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
