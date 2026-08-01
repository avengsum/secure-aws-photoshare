variable "ami_id" {
  description = "AMI ID for EC2"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ec2_security_group_id" {
  description = "Security Group ID for EC2"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM Instance Profile Name"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

variable "photo_bucket_name" {
  description = "Private S3 bucket for accepted photo uploads"
  type        = string
}

variable "quarantine_bucket_name" {
  description = "Private S3 bucket for rejected uploads"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used for S3 object encryption"
  type        = string
}

variable "domain_name" {
  description = "Domain name for ACM certificate and HTTPS. Leave empty to use HTTP only."
  type        = string
  default     = ""
}

variable "secret_arn" {
  description = "Secrets Manager ARN for database credentials"
  type        = string
}

variable "flask_session_secret_arn" {
  description = "Secrets Manager ARN for the shared Flask session secret"
  type        = string
}

variable "ecr_registry" {
  description = "ECR registry URL (account_id.dkr.ecr.region.amazonaws.com)"
  type        = string
}

variable "ecr_repository" {
  description = "ECR repository name"
  type        = string
  default     = "secure-photoshare"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
