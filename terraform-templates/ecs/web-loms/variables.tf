############################################
# variables.tf
# OBLIGATORIAS
############################################

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
}

variable "service_name" {
  description = "Base name of the service"
  type        = string
}

variable "environment" {
  description = "Environment name, for example dev, qa or prod"
  type        = string
}

variable "ecs_cluster" {
  description = "ECS cluster name or ARN where the service will be deployed"
  type        = string
}

variable "task_role_arn" {
  description = "IAM role ARN for the ECS task role"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM role ARN for the ECS task execution role"
  type        = string
}

variable "namespace" {
  description = "Cloud Map namespace name to be used by service discovery"
  type        = string
}

variable "application_load_balancer_arn" {
  description = "Application Load Balancer ARN"
  type        = string
}

variable "listener_rule_priority" {
  description = "Priority for the ALB listener rule"
  type        = number
}

############################################
# Opcionales
############################################

variable "listener_path_patterns" {
  description = "Path patterns for the listener rule"
  type        = list(string)
  default     = ["/*"]
}

variable "listener_host_headers" {
  description = "Dominios que atiende la regla del listener (vacío = cualquier dominio)"
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/SERVICE_NAME/health"
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "vpc_id" {
  description = "VPC ID. If empty, Terraform will try to use the only VPC found in the region"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Explicit subnet IDs to use. If empty, Terraform will try to discover them using subnet_prefix"
  type        = list(string)
  default     = []
}

variable "subnet_ids_csv" {
  description = "Comma-separated subnet IDs"
  type        = string
  default     = ""
}

variable "subnet_prefix" {
  description = "Prefix used to auto-discover subnets by Name tag, for example private or public"
  type        = string
  default     = "private"
}

variable "log_retention_in_days" {
  description = "Retention in days for the CloudWatch log group"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "image_tag" {
  description = "Tag to be used from the ECR repository"
  type        = string
  default     = "latest"
}

variable "ecr_image_tag_mutability" {
  description = "ECR image tag mutability"
  type        = string
  default     = "IMMUTABLE"
}

variable "autoscaling_enabled" {
  description = "Enable ECS Service autoscaling"
  type        = bool
  default     = true
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of tasks for ECS Service autoscaling"
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of tasks for ECS Service autoscaling"
  type        = number
  default     = 6
}

variable "autoscaling_scale_out_cooldown" {
  description = "Scale out cooldown in seconds"
  type        = number
  default     = 60
}

variable "autoscaling_scale_in_cooldown" {
  description = "Scale in cooldown in seconds"
  type        = number
  default     = 120
}

variable "ecr_keep_last_images" {
  description = "How many latest images should remain active in ECR"
  type        = number
  default     = 1
}

variable "env_file_s3_bucket" {
  description = "S3 bucket that stores the ECS environment file"
  type        = string
  default     = ""
}