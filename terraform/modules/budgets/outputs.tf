output "total_budget_name" {
  value = aws_budgets_budget.total.name
}

output "ec2_budget_name" {
  value = aws_budgets_budget.ec2.name
}

output "s3_budget_name" {
  value = aws_budgets_budget.s3.name
}
