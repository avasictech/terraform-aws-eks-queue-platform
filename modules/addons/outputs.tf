output "keda_operator_role_name" {
  description = "Pass to queue-autoscaler so it can grant KEDA read access to one queue."
  value       = aws_iam_role.keda_operator.name
}

output "keda_operator_role_arn" {
  value = aws_iam_role.keda_operator.arn
}
