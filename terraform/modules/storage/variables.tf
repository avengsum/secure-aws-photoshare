variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
}

variable "quarantine_bucket_name" {
  description = "S3 bucket name for suspicious or rejected uploads"
  type        = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "db_security_group_id" {
  type = string
}

variable "db_username" {
  default = "admin"
}

variable "db_name" {
  description = "Initial application database name"
  type        = string
  default     = "photoshare"
}

variable "db_backup_retention_days" {
  description = "Number of days to retain RDS automated backups"
  type        = number
  default     = 0
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for the RDS instance"
  type        = bool
  default     = true
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for the RDS instance"
  type        = bool
  default     = false
}
