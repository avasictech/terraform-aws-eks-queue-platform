variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  type    = string
  default = "queue-platform"
}

variable "api_image" {
  description = "Image built from app/api."
  type        = string
  default     = "ghcr.io/example/queue-platform-api:0.1.0"
}

variable "worker_image" {
  description = "Image built from app/worker."
  type        = string
  default     = "ghcr.io/example/queue-platform-worker:0.1.0"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint, e.g. [\"203.0.113.10/32\"]. No default on purpose."
  type        = list(string)

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "Set api_allowed_cidrs to your own IP range, not 0.0.0.0/0."
  }
}
