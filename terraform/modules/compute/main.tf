locals {
  enable_https = var.domain_name != ""
}

resource "aws_acm_certificate" "app" {
  count             = local.enable_https ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "photoshare-cert"
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "photoshare-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [
    var.ec2_security_group_id
  ]

  iam_instance_profile {
    name = var.instance_profile_name
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    photo_bucket_name        = var.photo_bucket_name
    quarantine_bucket_name   = var.quarantine_bucket_name
    kms_key_arn              = var.kms_key_arn
    secret_arn               = var.secret_arn
    flask_session_secret_arn = var.flask_session_secret_arn
    aws_region               = var.aws_region
    ecr_registry             = var.ecr_registry
    ecr_repository           = var.ecr_repository
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    #checkov:skip=CKV_AWS_341:Containerized Flask requires hop limit 2 for role credentials; IMDSv2 remains required and metadata tags are disabled.
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "photoshare-app"
    }
  }
}

resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB; private EC2 targets accept traffic only from the ALB security group.
  name     = "photoshare-tg"
  port     = 80
  protocol = "HTTP"

  vpc_id = var.vpc_id

  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }

  tags = {
    Name = "photoshare-target-group"
  }
}

resource "aws_lb" "app" {
  #checkov:skip=CKV2_AWS_28:WAF association is managed by module.monitoring.aws_wafv2_web_acl_association.alb.
  #checkov:skip=CKV2_AWS_20:HTTP redirects to HTTPS when domain_name is configured; the HTTP-only fallback is documented for this portfolio deployment.
  name     = "photoshare-alb"
  internal = false

  load_balancer_type = "application"

  security_groups = [
    var.alb_security_group_id
  ]

  subnets = var.public_subnet_ids

  drop_invalid_header_fields = true

  enable_deletion_protection = !var.allow_destructive_destroy

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name = "photoshare-alb"
  }
}

resource "aws_s3_bucket" "alb_logs" {
  #checkov:skip=CKV_AWS_18:This is a dedicated ALB log destination; self-logging would create a logging loop.
  #checkov:skip=CKV2_AWS_62:This is a load-balancer log destination, not an application event source.
  #checkov:skip=CKV_AWS_144:Cross-region replication is disabled for this single-region portfolio deployment.
  #checkov:skip=CKV2_AWS_61:Lifecycle configuration is declared below for this bucket.
  #checkov:skip=CKV_AWS_145:ALB access logs use the AWS-supported SSE-S3 encryption because ALB log delivery does not support this customer KMS key configuration.
  bucket        = "${var.photo_bucket_name}-alb-logs"
  force_destroy = var.allow_destructive_destroy
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowALBAccessLogs"
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/*"
    }]
  })
}

resource "aws_autoscaling_group" "app" {
  name             = "photoshare-asg"
  desired_capacity = 2
  min_size         = 2
  max_size         = 4

  vpc_zone_identifier = var.private_subnet_ids

  target_group_arns = [
    aws_lb_target_group.app.arn
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }

  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "photoshare-ec2"
    propagate_at_launch = true
  }
}

resource "aws_lb_listener" "https" {
  count             = local.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.app[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = local.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "http" {
  count             = local.enable_https ? 0 : 1
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  #checkov:skip=CKV_AWS_103:This is the HTTP-only development fallback; TLS is enforced by the HTTPS listener when domain_name is configured.

  #checkov:skip=CKV_AWS_2:This listener is the documented HTTP-only development fallback; production uses the HTTPS listener.

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
