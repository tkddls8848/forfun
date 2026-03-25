resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# Bastion 전용 서브넷 (유일한 외부 진입점)
resource "aws_subnet" "bastion" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-subnet-bastion" }
}

# k8s 서브넷: master-1, worker-1~N (프라이빗 — Bastion 경유)
resource "aws_subnet" "k8s" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false
  tags = { Name = "${var.project_name}-subnet-k8s" }
}

# NSD 서브넷: nsd-1, nsd-2 (프라이빗 — Bastion 경유)
resource "aws_subnet" "nsd" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false
  tags = { Name = "${var.project_name}-subnet-nsd" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-rt" }
}

resource "aws_route_table_association" "bastion" {
  subnet_id      = aws_subnet.bastion.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "k8s" {
  subnet_id      = aws_subnet.k8s.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "nsd" {
  subnet_id      = aws_subnet.nsd.id
  route_table_id = aws_route_table.main.id
}

output "vpc_id"           { value = aws_vpc.main.id }
output "subnet_bastion_id" { value = aws_subnet.bastion.id }
output "subnet_k8s_id"    { value = aws_subnet.k8s.id }
output "subnet_nsd_id"    { value = aws_subnet.nsd.id }
