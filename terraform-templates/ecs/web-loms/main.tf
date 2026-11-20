############################################
# main.tf
#
############################################

locals {
  service_full_name = "${var.service_name}-${var.environment}"

  target_group_base = replace(local.service_full_name, "_", "-")
  target_group_name = (
    length("${local.target_group_base}-tg") <= 32
    ? "${local.target_group_base}-tg"
    : "${substr(local.target_group_base, 0, 29)}-tg"
  )

  resolved_vpc_id = var.vpc_id != "" ? var.vpc_id : element(data.aws_vpcs.all.ids, 0)

  effective_health_check_path = (
    trimspace(var.health_check_path) == ""
    ? "/${var.service_name}/health"
    : (
        substr(var.health_check_path, 0, 1) == "/"
        ? var.health_check_path
        : "/${var.health_check_path}"
      )
  )

  effective_subnet_prefix = (
    lower(var.subnet_prefix) == "public"
    ? "public"
    : "private"
  )

  effective_ecr_image_tag_mutability = (
    upper(var.ecr_image_tag_mutability) == "MUTABLE"
    ? "MUTABLE"
    : "IMMUTABLE"
  )

  explicit_subnet_ids = (
    trimspace(var.subnet_ids_csv) != ""
    ? split(",", replace(var.subnet_ids_csv, " ", ""))
    : []
  )

  resolved_subnet_ids = length(local.explicit_subnet_ids) > 0 ? local.explicit_subnet_ids : [
    for s in data.aws_subnet.by_id :
    s.id
    if startswith(lower(lookup(s.tags, "Name", "")), local.effective_subnet_prefix)
  ]

  env_file_key = "${var.service_name}/${var.service_name}.env"
  env_file_arn = var.env_file_s3_bucket != "" ? "arn:aws:s3:::${var.env_file_s3_bucket}/${local.env_file_key}" : ""

#  execution_role_name = element(
#    split("/", var.execution_role_arn),
#    length(split("/", var.execution_role_arn)) - 1
#  )

  common_tags = merge(
    {
      Name        = local.service_full_name
      Service     = var.service_name
      Environment = var.environment
    },
    var.tags
  )
}

############################################
# Lookups
############################################

data "aws_vpcs" "all" {}

data "aws_vpc" "selected" {
  id = local.resolved_vpc_id
}

# Obtiene todas las subnets de la VPC
data "aws_subnets" "all_in_vpc" {
  filter {
    name   = "vpc-id"
    values = [local.resolved_vpc_id]
  }
}

# Lee el detalle de cada subnet para filtrar por prefijo del tag Name
data "aws_subnet" "by_id" {
  for_each = toset(data.aws_subnets.all_in_vpc.ids)
  id       = each.value
}

data "aws_lb_listener" "https" {
  load_balancer_arn = var.application_load_balancer_arn
  port              = 443
}

data "aws_service_discovery_dns_namespace" "this" {
  name = var.namespace
  type = "DNS_PRIVATE"
}

############################################
# CloudWatch Logs
############################################

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.service_name}"
  retention_in_days = var.log_retention_in_days
  tags              = local.common_tags
}

############################################
# Security Group
############################################

resource "aws_security_group" "this" {
  name        = "${local.service_full_name}-sg"
  description = "Security Group for ECS service ${local.service_full_name}"
  vpc_id      = local.resolved_vpc_id
  tags        = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "app_8080_from_vpc" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  description       = "Allow 8080 from VPC CIDR"
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound"
}

############################################
# Service Discovery (Cloud Map)
############################################

resource "aws_service_discovery_service" "this" {
  name = var.service_name

  dns_config {
    namespace_id   = data.aws_service_discovery_dns_namespace.this.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 300
      type = "A"
    }
  }

  health_check_custom_config {}

  tags = local.common_tags
}

############################################
# Load Balancer
############################################

resource "aws_lb_target_group" "this" {
  name                 = local.target_group_name
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = local.resolved_vpc_id
  target_type          = "ip"
  deregistration_delay = 300

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = local.effective_health_check_path
    port                = "traffic-port"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = local.common_tags
}

# Regla en listener 443 para mandar tráfico al target group creado.
# Si tu listener/rules ya las manejas en otro módulo, puedes omitir este recurso.
resource "aws_lb_listener_rule" "this" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = var.listener_path_patterns
    }
  }

  # Front servido por dominio en el ALB compartido: sin esta condición, "/*"
  # se llevaría el tráfico de todos los servicios con prioridad mayor.
  dynamic "condition" {
    for_each = length(var.listener_host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.listener_host_headers
      }
    }
  }

  tags = local.common_tags
}

############################################
# ECR Container Registry
############################################

resource "aws_ecr_repository" "this" {
  name                 = local.service_full_name
  image_tag_mutability = local.effective_ecr_image_tag_mutability

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last ${var.ecr_keep_last_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_keep_last_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

############################################
# ECS Task Definition
############################################

resource "aws_ecs_task_definition" "this" {
  family                   = local.service_full_name
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = local.service_full_name
      image = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
      cpu       = 0
      essential = true

      portMappings = [
        {
          name          = "${local.service_full_name}-8080-tcp"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment      = []
#      environmentFiles = []
      environmentFiles = var.env_file_s3_bucket != "" ? [
        {
          value = local.env_file_arn
          type  = "s3"
        }
      ] : []
      mountPoints      = []
      volumesFrom      = []
      ulimits          = []
      systemControls   = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
        secretOptions = []
      }
    }
  ])

  tags = local.common_tags
}

############################################
# ECS Service
############################################

resource "aws_ecs_service" "this" {
  name                               = local.service_full_name
  cluster                            = var.ecs_cluster
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 300
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"

  network_configuration {
    subnets          = local.resolved_subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this.arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.service_full_name
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener_rule.this
  ]

  tags = local.common_tags
}

############################################
# ECS Service Autoscaling
############################################

resource "aws_appautoscaling_target" "ecs_service" {
  count = var.autoscaling_enabled ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${var.ecs_cluster}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_scale_out_cpu" {
  count = var.autoscaling_enabled ? 1 : 0

  name               = "${local.service_full_name}-scale-out-cpu"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.autoscaling_scale_out_cooldown
    metric_aggregation_type = "Average"

    # > 60%  => +1
    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 15
      scaling_adjustment          = 1
    }

    # > 75% => +2 total
    step_adjustment {
      metric_interval_lower_bound = 15
      metric_interval_upper_bound = 25
      scaling_adjustment          = 2
    }

    # > 85% => +3 total
    step_adjustment {
      metric_interval_lower_bound = 25
      scaling_adjustment          = 3
    }
  }
}

resource "aws_appautoscaling_policy" "ecs_scale_in_cpu" {
  count = var.autoscaling_enabled ? 1 : 0

  name               = "${local.service_full_name}-scale-in-cpu"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.autoscaling_scale_in_cooldown
    metric_aggregation_type = "Average"

    # < 55% => -1
    step_adjustment {
      metric_interval_upper_bound = 20
      scaling_adjustment          = -1
    }

    # < 35% => -2 total
    step_adjustment {
      metric_interval_lower_bound = 20
      scaling_adjustment          = -2
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  count = var.autoscaling_enabled ? 1 : 0

  alarm_name          = "${local.service_full_name}-cpu-high"
  alarm_description   = "Scale out ECS service when CPU is above 60%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 60

  dimensions = {
    ClusterName = var.ecs_cluster
    ServiceName = aws_ecs_service.this.name
  }

  alarm_actions = [
    aws_appautoscaling_policy.ecs_scale_out_cpu[0].arn
  ]
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_low" {
  count = var.autoscaling_enabled ? 1 : 0

  alarm_name          = "${local.service_full_name}-cpu-low"
  alarm_description   = "Scale in ECS service when CPU is below 55%"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 55

  dimensions = {
    ClusterName = var.ecs_cluster
    ServiceName = aws_ecs_service.this.name
  }

  alarm_actions = [
    aws_appautoscaling_policy.ecs_scale_in_cpu[0].arn
  ]
}