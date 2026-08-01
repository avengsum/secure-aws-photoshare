data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "photoshare-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "photoshare-igw"
  }
}

## public subnet a

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a"
  }

}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-b"
  }
}

resource "aws_subnet" "private_app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-app-a"
  }
}

resource "aws_subnet" "private_app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-app-b"
  }
}

resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-db-a"
  }
}

resource "aws_subnet" "private_db_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-db-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_a" {

  subnet_id = aws_subnet.public_a.id

  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {

  subnet_id = aws_subnet.public_b.id

  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {

  domain = "vpc"

  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "main" {

  allocation_id = aws_eip.nat.id

  subnet_id = aws_subnet.public_a.id

  tags = {
    Name = "photoshare-nat"
  }

  depends_on = [
    aws_internet_gateway.main
  ]
}

resource "aws_route_table" "private_app" {

  vpc_id = aws_vpc.main.id

  route {

    cidr_block = "0.0.0.0/0"

    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "private-app-route"
  }
}

resource "aws_route_table_association" "private_app_a" {

  subnet_id = aws_subnet.private_app_a.id

  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "private_app_b" {

  subnet_id = aws_subnet.private_app_b.id

  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table" "private_db" {

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private-db-route"
  }
}

resource "aws_route_table_association" "private_db_a" {

  subnet_id = aws_subnet.private_db_a.id

  route_table_id = aws_route_table.private_db.id
}

resource "aws_route_table_association" "private_db_b" {

  subnet_id = aws_subnet.private_db_b.id

  route_table_id = aws_route_table.private_db.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private_app.id,
    aws_route_table.private_db.id
  ]

  tags = {
    Name = "photoshare-s3-endpoint"
  }
}

resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "ALB Security Group"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  security_group_id            = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group" "ec2" {
  name        = "ec2-sg"
  description = "Security Group for EC2 App Instances"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_rds" {
  security_group_id            = aws_security_group.ec2.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_vpc_endpoints" {
  security_group_id            = aws_security_group.ec2.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.vpc_endpoints.id
}

resource "aws_vpc_security_group_egress_rule" "ec2_outbound_https" {
  security_group_id = aws_security_group.ec2.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "vpc-endpoints-sg"
  description = "Interface endpoint access from private app instances"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_to_vpc_endpoints" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ec2.id
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "secretsmanager",
    "kms",
    "logs",
    "ssm",
    "ssmmessages",
    "ec2messages"
  ])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_a.id, aws_subnet.private_app_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "photoshare-${each.key}-endpoint"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_to_ec2" {
  security_group_id            = aws_security_group.ec2.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group" "rds" {
  name   = "rds-sg"
  vpc_id = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_to_rds" {
  security_group_id            = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.ec2.id
}

