output "instance_id" {
  value = aws_instance.origin.id
}

output "instance_ipv6" {
  value = aws_instance.origin.ipv6_addresses[0]
}

output "backup_bucket" {
  value = aws_s3_bucket.backup.bucket
}

output "backend_repository" {
  value = aws_ecr_repository.app.repository_url
}

output "proxy_repository" {
  value = aws_ecr_repository.proxy.repository_url
}

output "backend_release_parameter" {
  value = aws_ssm_parameter.backend_release.name
}

output "proxy_release_parameter" {
  value = aws_ssm_parameter.proxy_release.name
}

output "frontend_url_parameter" {
  value = aws_ssm_parameter.frontend_url.name
}

output "cloudflared_image_parameter" {
  value = aws_ssm_parameter.cloudflared_image.name
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "operational_alert_topic_arn" {
  value = aws_sns_topic.operational_alerts.arn
}

output "operations_dashboard_name" {
  value = aws_cloudwatch_dashboard.staging.dashboard_name
}
