variable "aws_region" {
  description = "AWS region"

  type = string

  default = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "photoshare"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "dev"
}

variable "resource_suffix" {
  description = "Globally unique suffix for S3 bucket names"
  type        = string
  default     = "syed-2026"
}

variable "alert_email" {
  description = "Email address for SNS alerts"
  type        = string
}

variable "cloudtrail_bucket_name" {
  description = "S3 bucket name for CloudTrail logs"
  type        = string
}

variable "domain_name" {
  description = "Domain name for ACM certificate and HTTPS. Leave empty for HTTP only."
  type        = string
  default     = ""
}

variable "monthly_budget_limit" {
  description = "Total monthly budget limit in USD"
  type        = number
  default     = 50
}

variable "s3_budget_limit" {
  description = "Monthly S3 budget limit in USD"
  type        = number
  default     = 10
}

variable "ec2_budget_limit" {
  description = "Monthly EC2 budget limit in USD"
  type        = number
  default     = 30
}

variable "enable_managed_security_services" {
  description = "Enable GuardDuty, SecurityHub, and Inspector2 (requires active AWS paid subscriptions)"
  type        = bool
  default     = false
}

variable "disposable_mode" {
  description = "Allow destructive cleanup for a disposable sandbox. Keep false for normal portfolio or production deployments."
  type        = bool
  default     = false
}
