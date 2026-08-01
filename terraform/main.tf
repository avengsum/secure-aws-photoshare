data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux" {

  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

}

data "aws_region" "current" {}

locals {
  name_prefix            = "${var.project_name}-${var.environment}"
  photo_bucket_name      = "${local.name_prefix}-photos-${var.resource_suffix}"
  quarantine_bucket_name = "${local.name_prefix}-quarantine-${var.resource_suffix}"
  config_bucket_name     = "${local.name_prefix}-config-${var.resource_suffix}"
  ecr_registry           = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

resource "aws_ecr_repository" "app" {
  name                 = "secure-photoshare"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "secure-photoshare"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

module "network" {
  source = "./modules/network"

}

module "storage" {
  source = "./modules/storage"

  bucket_name            = local.photo_bucket_name
  quarantine_bucket_name = local.quarantine_bucket_name
  db_subnet_ids          = module.network.db_subnet_ids
  db_security_group_id   = module.network.db_security_group_id

}

module "security" {

  source = "./modules/security"

  bucket_arn               = module.storage.bucket_arn
  quarantine_bucket_arn    = module.storage.quarantine_bucket_arn
  secret_arn               = module.storage.secret_arn
  flask_session_secret_arn = module.storage.flask_session_secret_arn
  kms_key_arn              = module.storage.kms_key_arn
  ecr_repository_arn       = aws_ecr_repository.app.arn

}

module "compute" {
  source = "./modules/compute"

  ami_id                   = data.aws_ami.amazon_linux.id
  vpc_id                   = module.network.vpc_id
  public_subnet_ids        = module.network.public_subnet_ids
  private_subnet_ids       = module.network.private_subnet_ids
  alb_security_group_id    = module.network.alb_security_group_id
  ec2_security_group_id    = module.network.ec2_security_group_id
  instance_profile_name    = module.security.instance_profile_name
  photo_bucket_name        = module.storage.bucket_name
  quarantine_bucket_name   = module.storage.quarantine_bucket_name
  kms_key_arn              = module.storage.kms_key_arn
  domain_name              = var.domain_name
  secret_arn               = module.storage.secret_arn
  flask_session_secret_arn = module.storage.flask_session_secret_arn
  ecr_registry             = local.ecr_registry
  ecr_repository           = aws_ecr_repository.app.name
  aws_region               = var.aws_region
}

module "monitoring" {

  source = "./modules/monitoring"

  vpc_id = module.network.vpc_id

  alb_arn                 = module.compute.alb_arn
  alb_arn_suffix          = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix

  email_address = var.alert_email

  cloudtrail_bucket_name = var.cloudtrail_bucket_name
  config_bucket_name     = local.config_bucket_name

  kms_key_arn      = module.storage.kms_key_arn
  db_identifier    = module.storage.db_identifier
  photo_bucket_arn = module.storage.bucket_arn

  enable_managed_security_services = var.enable_managed_security_services
}

module "budgets" {
  source = "./modules/budgets"

  alert_email          = var.alert_email
  monthly_budget_limit = var.monthly_budget_limit
  s3_budget_limit      = var.s3_budget_limit
  ec2_budget_limit     = var.ec2_budget_limit
}
