variable "deployment_name" {
  description = "Deployment to scale (the queue worker)."
  type        = string
}

variable "namespace" {
  type = string
}

variable "queue_url" {
  type = string
}

variable "queue_arn" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "keda_operator_role_name" {
  description = "From the addons module. This module grants it sqs:GetQueueAttributes on this queue only."
  type        = string
}

variable "messages_per_pod" {
  description = <<-EOT
    Target backlog per replica (KEDA `queueLength`). Desired replicas =
    ceil(backlog / messages_per_pod). Pick it as: messages one pod can clear
    within your latency target, e.g. 2 msg/s * 10 s target = 20.
  EOT
  type        = number
  default     = 20

  validation {
    condition     = var.messages_per_pod > 0
    error_message = "messages_per_pod must be greater than 0."
  }
}

variable "scale_on_in_flight" {
  description = "Count in-flight (received, not yet deleted) messages as backlog, so busy pods are not removed in the middle of a burst."
  type        = bool
  default     = true
}

variable "min_replicas" {
  description = "Set to 0 to allow scale-to-zero (adds cold-start latency on the first message)."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Cap. Also protects downstream systems (DB, APIs) from too many consumers."
  type        = number
  default     = 20
}

variable "activation_messages" {
  description = "Only used when min_replicas = 0: backlog above which KEDA wakes the worker from 0 to 1."
  type        = number
  default     = 0
}

variable "polling_interval" {
  description = "Seconds between KEDA queue checks (GetQueueAttributes)."
  type        = number
  default     = 15
}

variable "cooldown_period" {
  description = "Seconds of empty queue before scaling 1 -> 0. Only matters when min_replicas = 0."
  type        = number
  default     = 300
}

variable "scale_up" {
  description = "HPA scale-up behaviour. The larger of `pods` and `percent` per `period_seconds` wins."
  type = object({
    stabilization_seconds = number
    pods                  = number
    percent               = number
    period_seconds        = number
  })
  default = {
    stabilization_seconds = 0
    pods                  = 4
    percent               = 100
    period_seconds        = 15
  }
}

variable "scale_down" {
  description = "HPA scale-down behaviour. Slow on purpose: removing pods during a short lull just re-adds them a minute later."
  type = object({
    stabilization_seconds = number
    percent               = number
    period_seconds        = number
  })
  default = {
    stabilization_seconds = 300
    percent               = 50
    period_seconds        = 60
  }
}

variable "fallback_replicas" {
  description = "Replicas to run if KEDA cannot read the queue 3 times in a row (IAM or SQS outage). null disables fallback."
  type        = number
  default     = 2
}
