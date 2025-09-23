########################################
# Terraform + Provider
########################################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

########################################
# Locals
########################################
locals {
  prefix              = var.project_prefix
  app_base_name       = "${local.prefix}-fastapi-app"
  cluster_name        = "${local.prefix}-cluster"
  task_family         = "${local.prefix}-task"
  service_name        = "${local.prefix}-service"
  alb_name            = "${local.prefix}-alb"
  tg_name             = "${local.prefix}-tg"
  alb_sg_name         = "${local.prefix}-alb-sg"
  svc_sg_name         = "${local.prefix}-service-sg"
  log_group_name      = "/ecs/${local.prefix}-app"
  container_name      = "app"
  ecr_repository_name = "${local.prefix}-fastapi-app"
  health_check_path   = var.health_check_path
}

########################################
# Availability Zones (for subnet spread)
########################################
data "aws_availability_zones" "available" {}

########################################
# VPC + Internet Access (public only)
########################################
# VPC: isolated network
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${local.prefix}-vpc" }
}

# Internet gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.prefix}-igw" }
}

# Public subnets in 2 AZs (assign public IPs)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr_a
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = { Name = "${local.prefix}-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr_b
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags = { Name = "${local.prefix}-public-b" }
}

# Public route table with default route to the internet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

########################################
# ECR
########################################
resource "aws_ecr_repository" "repo" {
  name                 = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration { scan_on_push = true }
  tags = { Name = local.ecr_repository_name }
}

# Lifecycle: (keep last 30 images)
resource "aws_ecr_lifecycle_policy" "default" {
  repository = aws_ecr_repository.repo.name
  policy     = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Keep last 30 images",
      selection = {
        tagStatus   = "any",
        countType   = "imageCountMoreThan",
        countNumber = 30
      },
      action = { type = "expire" }
    }]
  })
}

########################################
# CloudWatch Logs
########################################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = local.log_group_name
  retention_in_days = 14
}

########################################
# IAM for ECS task execution (uses JSON policy)
########################################
# Trust policy: allow ecs-tasks.amazonaws.com to assume this role
data "aws_iam_policy_document" "ecs_task_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Role the task uses at start to pull image & write logs
resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.prefix}-ecs-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume.json
}

# customer-managed policy from JSON file
resource "aws_iam_policy" "ecs_task_exec_policy" {
  name   = "${local.prefix}-ecs-task-exec-policy"
  policy = file(var.exec_policy_json_path)
}

# Attach the custom policy to the role
resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach_custom" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_task_exec_policy.arn
}

########################################
# Security Groups
########################################
# ALB SG: allow HTTP from the world; egress all
resource "aws_security_group" "alb" {
  name        = local.alb_sg_name
  description = "ALB SG - allow HTTP 80 from anywhere"
  vpc_id      = aws_vpc.this.id

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = local.alb_sg_name }
}

# Service SG: only allow from ALB on app port; egress all
resource "aws_security_group" "service" {
  name        = local.svc_sg_name
  description = "Service SG - allow traffic only from ALB SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "From ALB on container port"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = local.svc_sg_name }
}

# SG for Interface VPC Endpoints: allow HTTPS from ECS service tasks only
# using vpc endpoints to cut off cost on NAT gateway
resource "aws_security_group" "vpce" {
  name        = "${local.prefix}-vpce-sg"
  description = "Allow HTTPS from ECS service to VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "TLS from service tasks"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.service.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "${local.prefix}-vpce-sg" }
}

# Gateway endpoint for S3 (lets tasks reach S3 privately via VPC routes)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = { Name = "${local.prefix}-vpce-s3" }
}

# ECR API (control plane for ECR)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id               = aws_vpc.this.id
  service_name         = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type    = "Interface"
  subnet_ids           = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_group_ids   = [aws_security_group.vpce.id]
  private_dns_enabled  = true
  tags = { Name = "${local.prefix}-vpce-ecr-api" }
}

# ECR DKR (docker registry endpoint for image layers/manifest)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id               = aws_vpc.this.id
  service_name         = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type    = "Interface"
  subnet_ids           = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_group_ids   = [aws_security_group.vpce.id]
  private_dns_enabled  = true
  tags = { Name = "${local.prefix}-vpce-ecr-dkr" }
}

# CloudWatch Logs (so tasks can write logs without public internet)
resource "aws_vpc_endpoint" "logs" {
  vpc_id               = aws_vpc.this.id
  service_name         = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type    = "Interface"
  subnet_ids           = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_group_ids   = [aws_security_group.vpce.id]
  private_dns_enabled  = true
  tags = { Name = "${local.prefix}-vpce-logs" }
}

########################################
# ALB + Target Group + Listener
########################################
# Internet-facing Application Load Balancer
resource "aws_lb" "this" {
  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags               = { Name = local.alb_name }
}

# Target group (ip mode for Fargate); health check /health expecting 200
resource "aws_lb_target_group" "this" {
  name        = local.tg_name
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = local.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
  }

  tags = { Name = local.tg_name }
}

# HTTP listener → forward to TG
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

########################################
# ECS Cluster, Task Definition, Service
########################################
# ECS cluster (control-plane)
resource "aws_ecs_cluster" "this" {
  name = local.cluster_name
  tags = { Name = local.cluster_name }
}

# Task definition
resource "aws_ecs_task_definition" "this" {
  family                   = local.task_family
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "${aws_ecr_repository.repo.repository_url}:${var.image_tag}" # CI updates var.image_tag
      essential = true
      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
        appProtocol   = "http"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
      environment = []
    }
  ])

  tags = { Name = local.task_family }
}

# Long-running service
resource "aws_ecs_service" "this" {
  name             = local.service_name
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.this.arn
  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    assign_public_ip = true
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
  tags       = { Name = local.service_name }
}

########################################
# Autoscaling
########################################
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_count
  min_capacity       = var.min_count
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_target" {
  name               = "${local.prefix}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

########################################
# CloudWatch Alarm (CPU > 70% for 2 min)
########################################
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.this.name
  }

  alarm_description = "CPU > 70% for ECS service ${aws_ecs_service.this.name}"
}