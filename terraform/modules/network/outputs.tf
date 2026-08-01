output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
}

output "private_subnet_ids" {
  value = [
    aws_subnet.private_app_a.id,
    aws_subnet.private_app_b.id
  ]
}

output "db_subnet_ids" {
  value = [
    aws_subnet.private_db_a.id,
    aws_subnet.private_db_b.id
  ]
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "ec2_security_group_id" {
  value = aws_security_group.ec2.id
}

output "db_security_group_id" {
  value = aws_security_group.rds.id
}
