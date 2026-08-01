variable "bucket_arn" {
  type = string
}

variable "quarantine_bucket_arn" {
  type = string
}

variable "secret_arn" {
  type = string
}

variable "flask_session_secret_arn" {
  description = "Secrets Manager ARN containing the shared Flask session secret"
  type        = string
}

variable "kms_key_arn" {
  type = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository for pull permissions"
  type        = string
}
