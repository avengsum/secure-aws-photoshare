variable "alert_email" {
  description = "Email address for budget alert notifications"
  type        = string
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 50
}

variable "s3_budget_limit" {
  description = "Monthly S3 storage budget in USD"
  type        = number
  default     = 10
}

variable "ec2_budget_limit" {
  description = "Monthly EC2 compute budget in USD"
  type        = number
  default     = 30
}
