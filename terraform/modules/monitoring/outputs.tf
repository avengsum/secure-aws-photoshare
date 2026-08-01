output "log_group_name" {
  value = aws_cloudwatch_log_group.photoshare.name
}

output "log_group_arn" {
  value = aws_cloudwatch_log_group.photoshare.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.photoshare.arn
}

output "guardduty_detector_id" {
  value = try(aws_guardduty_detector.main[0].id, null)
}

output "securityhub_enabled" {
  value = try(aws_securityhub_account.main[0].id, null)
}

output "access_analyzer_arn" {
  value = aws_accessanalyzer_analyzer.main.arn
}

output "inspector_enabled" {
  value = try(aws_inspector2_enabler.main[0].id, null)
}

output "flow_log_id" {
  value = aws_flow_log.vpc.id
}

output "waf_arn" {
  value = aws_wafv2_web_acl.main.arn
}