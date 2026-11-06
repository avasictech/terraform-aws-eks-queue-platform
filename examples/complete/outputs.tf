output "cluster_name" {
  value = module.cluster.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.cluster.cluster_name} --region ${var.region}"
}

output "queue_url" {
  value = aws_sqs_queue.jobs.url
}

output "dlq_url" {
  value = aws_sqs_queue.jobs_dlq.url
}

output "worker_hpa" {
  description = "kubectl -n jobs get hpa <this> -w  to watch scaling."
  value       = module.worker_autoscaler.hpa_name
}
