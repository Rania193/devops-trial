# TODO: Output ALB DNS name so we can access the app
output "alb_dns_name" {
  description = "Public ALB DNS"
  value       = aws_lb.app.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL to push your image"
  value       = aws_ecr_repository.app.repository_url
}

output "cluster_name" { value = aws_ecs_cluster.app.name }
output "service_name" { value = aws_ecs_service.app.name }
