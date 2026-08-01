output "inspector_enabled" {
  value = module.monitoring.inspector_enabled
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "github_actions_role_arn" {

  value = aws_iam_role.github_actions.arn
}