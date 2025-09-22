############################################
# Provider / Versions
############################################
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  profile = "personal1"
}

############################################
# Data sources
############################################
data "aws_iam_role" "ecs_task_execution" {
  arn = "arn:aws:iam::311141537104:user/DevOps_Candidate"
  name = "DevOps_Candidate"
}

data "aws_caller_identity" "current" {}

############################################
# Locals (naming & image)
############################################
locals {
  base         = "devops-trial-${var.project}"
  ecr_name     = "devops-trial-${var.ecr_repo_name}"
  cluster      = "${local.base}-cluster"
  log_group    = "/ecs/${local.base}-fastapi"
  tg_name      = "${local.base}-tg"
  alb_name     = "${local.base}-alb"
  alb_sg_name  = "${local.base}-alb-sg"
  task_sg_name = "${local.base}-task-sg"
  task_family  = "${local.base}-fastapi-task"
  service      = "${local.base}-fastapi-service"
}

############################################
# Networking: VPC, subnets, routes, IGW, NAT
############################################
resource "aws_vpc" "main" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.base}-vpc" }
}

# Public subnets (2 AZs)
resource "aws_subnet" "public" {
  for_each = {
    a = { az = "us-east-1a", cidr = "10.42.0.0/20" }
    b = { az = "us-east-1b", cidr = "10.42.16.0/20" }
  }
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true
  tags = { Name = "${local.base}-public-${each.key}" }
}

# Private subnets (2 AZs)
resource "aws_subnet" "private" {
  for_each = {
    a = { az = "us-east-1a", cidr = "10.42.32.0/20" }
    b = { az = "us-east-1b", cidr = "10.42.48.0/20" }
  }
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags = { Name = "${local.base}-private-${each.key}" }
}

# Internet Gateway for public subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.base}-igw" }
}

# One NAT Gateway (cost-friendly) in public subnet a
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.base}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["a"].id
  tags          = { Name = "${local.base}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.base}-public-rt" }
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.base}-private-rt" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

############################################
# Security Groups
############################################
resource "aws_security_group" "alb" {
  name        = local.alb_sg_name
  description = "Allow HTTP inbound to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP IPv4"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description      = "HTTP IPv6"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = local.alb_sg_name }
}

resource "aws_security_group" "task" {
  name        = local.task_sg_name
  description = "Allow app traffic from ALB on 8000"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB SG on 8000"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = local.task_sg_name }
}

############################################
# Load Balancer, Target Group, Listener
############################################
resource "aws_lb" "app" {
  name               = local.alb_name
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
  tags               = { Name = local.alb_name }
}

resource "aws_lb_target_group" "app" {
  name        = local.tg_name
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = { Name = local.tg_name }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

############################################
# ECR Repository
############################################
resource "aws_ecr_repository" "app" {
  name = local.ecr_name
  image_scanning_configuration { scan_on_push = true }
  force_delete = true
  tags = { Name = local.ecr_name }
}

############################################
# CloudWatch Logs
############################################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = local.log_group
  retention_in_days = 14
}

############################################
# ECS Cluster
############################################
resource "aws_ecs_cluster" "app" {
  name = local.cluster
}


############################################
# ECS Task Definition (Fargate)
############################################
resource "aws_ecs_task_definition" "app" {
  family                   = local.task_family
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "fastapi",
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}",
      essential = true,
      portMappings = [{
        containerPort = 8000,
        hostPort      = 8000,
        protocol      = "tcp"
      }],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name,
          awslogs-region        = var.aws_region,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

############################################
# ECS Service
############################################
resource "aws_ecs_service" "app" {
  name            = local.service
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "fastapi"
    container_port   = 8000
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

############################################
# Application Auto Scaling (70% CPU)
############################################
resource "aws_appautoscaling_target" "ecs" {
  min_capacity       = var.min_count
  max_capacity       = var.max_count
  resource_id        = "service/${aws_ecs_cluster.app.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_target_tracking" {
  name               = "${local.base}-ecs-cpu-70"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

############################################
# Monitoring: CloudWatch Alarm for high CPU (>70%)
############################################
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "devops-trial-${local.service}-high-cpu"
  alarm_description   = "ECS service average CPU > 70%"

  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.app.name
    ServiceName = aws_ecs_service.app.name
  }
}
