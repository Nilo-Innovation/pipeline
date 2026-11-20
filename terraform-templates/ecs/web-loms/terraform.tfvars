############################################
# REQUIRED VARIABLES
############################################

aws_region                    = "AWS_REGION"
service_name                  = "SERVICE_NAME"
environment                   = "ENVIRONMENT"
ecs_cluster                   = "ECS_CLUSTER"
task_role_arn                 = "TASK_ROLE_ARN"
execution_role_arn            = "EXECUTION_ROLE_ARN"
namespace                     = "NAMESPACE"
application_load_balancer_arn = "APPLICATION_LOAD_BALANCER_ARN"
listener_rule_priority        = LISTENER_RULE_PRIORITY
autoscaling_min_capacity      = DESIRED_COUNT
autoscaling_enabled            = true
autoscaling_max_capacity       = 6
autoscaling_scale_out_cooldown = 60
autoscaling_scale_in_cooldown  = 120
env_file_s3_bucket             = "ENV_FILE_S3_BUCKET"

ecr_keep_last_images           = 2

############################################
# OPTIONAL VARIABLES
############################################

image_tag                = "IMAGE_TAG"
ecr_image_tag_mutability = "IMMUTABLE"
listener_path_patterns   = ["/*"]
listener_host_headers    = ["loms.lineup.com.mx"]
health_check_path        = "SERVICE_NAME/HEALTH_CHECK_PATH"
desired_count            = DESIRED_COUNT
vpc_id                   = "VPC_ID"
subnet_ids_csv           = "SUBNET_IDS_CSV"
subnet_prefix            = "SUBNET_PREFIX"
log_retention_in_days    = LOG_RETENTION_IN_DAYS
tags                     = {}