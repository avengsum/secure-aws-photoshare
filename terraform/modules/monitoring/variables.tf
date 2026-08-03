variable "email_address" {
  description = "Email address for CloudWatch alerts"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 365
}

variable "cloudtrail_bucket_name" {
  description = "S3 bucket for CloudTrail logs"
  type        = string
}

variable "config_bucket_name" {
  description = "S3 bucket for AWS Config delivery"
  type        = string
}

variable "kms_key_arn" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "alb_arn" {
  description = "Application Load Balancer ARN"
  type        = string
}

variable "alb_arn_suffix" {
  description = "Application Load Balancer ARN suffix for CloudWatch metrics"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target Group ARN suffix for CloudWatch metrics"
  type        = string
}

variable "db_identifier" {
  description = "RDS database identifier for CloudWatch metrics"
  type        = string
}

variable "photo_bucket_arn" {
  description = "Photo bucket ARN for CloudTrail S3 data events"
  type        = string
}

variable "enable_managed_security_services" {
  description = "Enable GuardDuty, SecurityHub, and Inspector2"
  type        = bool
  default     = false
}

variable "allow_destructive_destroy" {
  description = "Allow deletion of audit buckets in a disposable environment."
  type        = bool
  default     = false
}
