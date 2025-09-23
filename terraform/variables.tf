variable "region"    { default = "eu-west-1" }
variable "project"       { default = "devops-trial" }
variable "ecr_repo_name" { default = "fastapi-app" }
variable "image_tag"     { default = "latest" }

variable "task_cpu"    { default = "256" }
variable "task_memory" { default = "512" }

variable "desired_count" { default = 1 }
variable "min_count"     { default = 1 }
variable "max_count"     { default = 3 }

variable "project_prefix" {
  description = "All resource names will start with this (devops-trial-*)."
  type        = string
  default     = "devops-trial"
}

variable "vpc_cidr" {
  description = "CIDR for the new VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr_a" {
  description = "CIDR for public subnet A."
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_cidr_b" {
  description = "CIDR for public subnet B."
  type        = string
  default     = "10.0.2.0/24"
}

variable "container_port" {
  description = "FastAPI container port."
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "ALB health check path."
  type        = string
  default     = "/health"
}

variable "exec_policy_json_path" {
  description = "File path to the JSON policy for ECS task execution"
  type        = string
  default     = "../policies/devops-trial-iam.json"
}