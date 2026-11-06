output "scaled_object_name" {
  value = local.name
}

output "hpa_name" {
  description = "KEDA creates and owns this HPA; inspect it with kubectl describe hpa."
  value       = "keda-hpa-${local.name}"
}
