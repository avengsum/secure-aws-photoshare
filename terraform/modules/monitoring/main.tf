data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "photoshare" {
  name              = "/photoshare/application"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/photoshare"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_iam_role" "cloudtrail_logs" {
  name = "photoshare-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  name = "photoshare-cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

resource "aws_sns_topic" "alerts" {
  name              = "photoshare-alerts"
  kms_master_key_id = var.kms_key_arn
}

## email
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email_address
}


resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAWSMonitoringServicesToPublish"
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudwatch.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}




resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "HighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm when EC2 CPU exceeds 80%"
  alarm_actions = [
    aws_sns_topic.alerts.arn
  ]
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "PhotoShareALB5xxErrors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alarm when the ALB returns elevated 5xx responses"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
  alarm_actions = [
    aws_sns_topic.alerts.arn
  ]
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "PhotoShareUnhealthyTargets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alarm when the target group has unhealthy instances"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
  alarm_actions = [
    aws_sns_topic.alerts.arn
  ]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "PhotoShareRDSHighCPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm when RDS CPU exceeds 80%"
  dimensions = {
    DBInstanceIdentifier = var.db_identifier
  }
  alarm_actions = [
    aws_sns_topic.alerts.arn
  ]
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "PhotoShareRDSLowFreeStorage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648
  alarm_description   = "Alarm when RDS free storage drops below 2 GiB"
  dimensions = {
    DBInstanceIdentifier = var.db_identifier
  }
  alarm_actions = [
    aws_sns_topic.alerts.arn
  ]
}

#checkov:skip=CKV_AWS_18:Central audit bucket; access logging would create an unnecessary logging loop.
#checkov:skip=CKV_AWS_144:Cross-region replication is disabled for this single-region portfolio deployment.
#checkov:skip=CKV2_AWS_62:CloudTrail delivery buckets are service destinations, not application event sources.
resource "aws_s3_bucket" "cloudtrail" {
  #checkov:skip=CKV_AWS_18:Central audit bucket does not self-log.
  #checkov:skip=CKV_AWS_144:Single-region portfolio deployment.
  #checkov:skip=CKV2_AWS_62:Service destination bucket, not an application event source.
  bucket        = var.cloudtrail_bucket_name
  force_destroy = true

}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {

  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail" {

  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-old-audit-logs"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }

  }

}

resource "aws_cloudtrail" "photoshare" {
  name                          = "photoshare-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  kms_key_id                    = var.kms_key_arn
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true
  sns_topic_name                = aws_sns_topic.alerts.name
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_logs.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type = "AWS::S3::Object"
      values = [
        "${var.photo_bucket_arn}/"
      ]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {

  statement {

    sid = "AWSCloudTrailAclCheck"

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl"
    ]

    resources = [
      aws_s3_bucket.cloudtrail.arn
    ]
  }

  statement {

    sid = "AWSCloudTrailWrite"

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"
    ]

    condition {

      test = "StringEquals"

      variable = "s3:x-amz-acl"

      values = [
        "bucket-owner-full-control"
      ]
    }
  }

}

resource "aws_s3_bucket_policy" "cloudtrail" {

  bucket = aws_s3_bucket.cloudtrail.id

  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json

}

resource "aws_iam_role" "flow_logs" {

  name = "photoshare-flowlogs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}


resource "aws_iam_role" "config_role" {

  name = "photoshare-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "config.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config" {

  role = aws_iam_role.config_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"

}

#checkov:skip=CKV_AWS_18:Central Config delivery bucket; access logging would require another bucket and create unnecessary audit noise.
#checkov:skip=CKV_AWS_144:Cross-region replication is disabled for this single-region portfolio deployment.
#checkov:skip=CKV2_AWS_62:AWS Config delivery buckets are service destinations, not application event sources.
resource "aws_s3_bucket" "config" {
  #checkov:skip=CKV_AWS_18:Central Config bucket does not self-log.
  #checkov:skip=CKV_AWS_144:Single-region portfolio deployment.
  #checkov:skip=CKV2_AWS_62:Service destination bucket, not an application event source.

  bucket = var.config_bucket_name

}

resource "aws_s3_bucket_public_access_block" "config" {

  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true

}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    id     = "expire-old-config-snapshots"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {

  bucket = aws_s3_bucket.config.id

  rule {

    apply_server_side_encryption_by_default {

      sse_algorithm = "aws:kms"

      kms_master_key_id = var.kms_key_arn

    }
  }

}

data "aws_iam_policy_document" "config_s3_policy" {
  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_s3_policy.json
}

resource "aws_config_configuration_recorder" "main" {
  name     = "photoshare-config"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "photoshare-delivery"
  s3_bucket_name = aws_s3_bucket.config.id

  s3_kms_key_arn = var.kms_key_arn

  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.config,
    aws_s3_bucket_server_side_encryption_configuration.config
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [
    aws_config_delivery_channel.main
  ]
}

resource "aws_config_config_rule" "restricted_ssh" {
  name = "restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [
    aws_config_configuration_recorder_status.main, aws_config_configuration_recorder.main,
    aws_config_delivery_channel.main
  ]
}

resource "aws_config_config_rule" "security_baseline" {
  for_each = {
    s3_public_read_prohibited  = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    s3_public_write_prohibited = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
    rds_storage_encrypted      = "RDS_STORAGE_ENCRYPTED"
    rds_public_access_check    = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
    cloudtrail_enabled         = "CLOUD_TRAIL_ENABLED"
    encrypted_volumes          = "ENCRYPTED_VOLUMES"
    root_account_mfa_enabled   = "ROOT_ACCOUNT_MFA_ENABLED"
    iam_user_no_policies_check = "IAM_USER_NO_POLICIES_CHECK"
  }

  name = each.key

  source {
    owner             = "AWS"
    source_identifier = each.value
  }

  depends_on = [
    aws_config_configuration_recorder_status.main
  ]
}

resource "aws_guardduty_detector" "main" {
  #checkov:skip=CKV2_AWS_3:GuardDuty is opt-in because the account requires a paid service subscription.
  count  = var.enable_managed_security_services ? 1 : 0
  enable = true
}

resource "aws_guardduty_detector_feature" "s3_protection" {
  count       = var.enable_managed_security_services ? 1 : 0
  detector_id = aws_guardduty_detector.main[0].id

  name = "S3_DATA_EVENTS"

  status = "ENABLED"
}

resource "aws_securityhub_account" "main" {
  count = var.enable_managed_security_services ? 1 : 0
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count         = var.enable_managed_security_services ? 1 : 0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [
    aws_securityhub_account.main
  ]
}

resource "aws_inspector2_enabler" "main" {
  count = var.enable_managed_security_services ? 1 : 0

  account_ids = [
    data.aws_caller_identity.current.account_id
  ]

  resource_types = [
    "EC2",
    "ECR"
  ]
}

resource "aws_accessanalyzer_analyzer" "main" {

  analyzer_name = "photoshare-access-analyzer"
  type          = "ACCOUNT"
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count       = var.enable_managed_security_services ? 1 : 0
  name        = "photoshare-guardduty-findings"
  description = "Send GuardDuty findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_findings" {
  count     = var.enable_managed_security_services ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alerts.arn
}

resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  count       = var.enable_managed_security_services ? 1 : 0
  name        = "photoshare-securityhub-findings"
  description = "Send high severity Security Hub findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "securityhub_findings" {
  count     = var.enable_managed_security_services ? 1 : 0
  rule      = aws_cloudwatch_event_rule.securityhub_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alerts.arn
}

resource "aws_iam_role_policy" "flow_logs" {

  name = "photoshare-flowlogs-policy"

  role = aws_iam_role.flow_logs.id

  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Effect = "Allow"

        Action = [

          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"

        ]

        Resource = [
          aws_cloudwatch_log_group.photoshare.arn,
          "${aws_cloudwatch_log_group.photoshare.arn}:*"
        ]

      }

    ]

  })

}

resource "aws_flow_log" "vpc" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.photoshare.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-photoshare"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_wafv2_web_acl" "main" {

  name = "photoshare-waf"

  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {

    cloudwatch_metrics_enabled = true

    metric_name = "photoshare-waf"

    sampled_requests_enabled = true

  }

  rule {

    name = "AWSCommonRules"

    priority = 1

    override_action {
      none {}
    }

    statement {

      managed_rule_group_statement {

        vendor_name = "AWS"

        name = "AWSManagedRulesCommonRuleSet"

        rule_action_override {
          name = "SizeRestrictions_BODY"

          action_to_use {
            count {}
          }
        }

      }

    }

    visibility_config {

      cloudwatch_metrics_enabled = true

      metric_name = "AWSCommonRules"

      sampled_requests_enabled = true

    }

  }

  rule {
    name     = "AWSKnownBadInputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSKnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSSQLiRules"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSSQLiRules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSIpReputation"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSIpReputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitByIp"
    priority = 5

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitByIp"
      sampled_requests_enabled   = true
    }
  }

}

resource "aws_wafv2_web_acl_association" "alb" {

  resource_arn = var.alb_arn

  web_acl_arn = aws_wafv2_web_acl.main.arn

}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  resource_arn = aws_wafv2_web_acl.main.arn
  log_destination_configs = [
    aws_cloudwatch_log_group.waf.arn
  ]
}
