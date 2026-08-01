output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "launch_template_id" {
  value = aws_launch_template.app.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}

output "alb_arn" {
  value = aws_lb.app.arn
}

output "alb_arn_suffix" {
  value = aws_lb.app.arn_suffix
}

output "certificate_validation_records" {
  description = "DNS records to create for ACM certificate validation"
  value = [
    for dvo in flatten([for cert in aws_acm_certificate.app : cert.domain_validation_options]) : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  ]
}
