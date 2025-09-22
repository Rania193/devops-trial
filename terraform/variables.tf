variable "aws_region"    { default = "us-east-1" }
variable "project"       { default = "devops-trial" }
variable "ecr_repo_name" { default = "fastapi-app" }
variable "image_tag"     { default = "latest" }

variable "task_cpu"    { default = "256" }
variable "task_memory" { default = "512" }

variable "desired_count" { default = 1 }
variable "min_count"     { default = 1 }
variable "max_count"     { default = 3 }

variable "execution_role_name" {
  description = "Name of the existing ECS task execution role"
  type        = string
  default     = "DevOps_Candidate"
}
