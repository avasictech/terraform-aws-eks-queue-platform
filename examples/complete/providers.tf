provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# All three Kubernetes-facing providers get a short-lived token from
# `aws eks get-token`, so no kubeconfig is needed.
locals {
  k8s_host = module.cluster.cluster_endpoint
  k8s_ca   = base64decode(module.cluster.cluster_certificate_authority_data)
  k8s_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.cluster.cluster_name, "--region", var.region]
  }
}

provider "kubernetes" {
  host                   = local.k8s_host
  cluster_ca_certificate = local.k8s_ca

  exec {
    api_version = local.k8s_exec.api_version
    command     = local.k8s_exec.command
    args        = local.k8s_exec.args
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.k8s_host
    cluster_ca_certificate = local.k8s_ca
    exec                   = local.k8s_exec
  }
}

provider "kubectl" {
  host                   = local.k8s_host
  cluster_ca_certificate = local.k8s_ca
  load_config_file       = false

  exec {
    api_version = local.k8s_exec.api_version
    command     = local.k8s_exec.command
    args        = local.k8s_exec.args
  }
}
