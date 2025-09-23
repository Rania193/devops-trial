# TODO: Output ALB DNS name so we can access the app
output "alb_dns_name" {
  description = "Public DNS name for the ALB (open http://<dns>/health)"
  value       = aws_lb.this.dns_name
}

output "ecr_repository_url" {
  description = "Push images here"
  value       = aws_ecr_repository.repo.repository_url
}

output "vpc_id" {
  value       = aws_vpc.this.id
  description = "Created VPC ID"
}

output "public_subnet_ids" {
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  description = "Created public subnet IDs"
}
