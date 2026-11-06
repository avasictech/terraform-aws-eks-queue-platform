output "deployment_name" {
  value = kubernetes_deployment_v1.this.metadata[0].name
}

output "service_account_name" {
  value = kubernetes_service_account_v1.this.metadata[0].name
}

output "iam_role_arn" {
  value = aws_iam_role.this.arn
}

output "iam_role_name" {
  value = aws_iam_role.this.name
}

output "service_name" {
  value = var.container_port == null ? null : kubernetes_service_v1.this[0].metadata[0].name
}
