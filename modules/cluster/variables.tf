variable "name" {
  description = "Cluster name. Also used as a prefix for IAM roles and the KMS key alias."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs and the node group (at least two AZs)."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint publicly. Off by default; turn it on only together with narrow public_access_cidrs."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint (only used when endpoint_public_access = true)."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "Instance types for the default managed node group."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  description = "Initial size only; later changes made by a node autoscaler are ignored."
  type        = number
  default     = 2
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "node_disk_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
