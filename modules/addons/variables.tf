variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "From the cluster module."
  type        = string
}

variable "oidc_issuer" {
  description = "From the cluster module (no https:// prefix)."
  type        = string
}

variable "keda_chart_version" {
  type    = string
  default = "2.21.0"
}

variable "external_secrets_chart_version" {
  type    = string
  default = "2.14.0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
