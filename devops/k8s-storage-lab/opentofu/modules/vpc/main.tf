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

resource "aws_subnet" "k8s" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-subnet-k8s" }
}

resource "aws_subnet" "nsd" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-subnet-nsd" }
}

resource "aws_subnet" "ceph" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-subnet-ceph" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-rt" }
}

resource "aws_route_table_association" "k8s" {
  subnet_id      = aws_subnet.k8s.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "nsd" {
  subnet_id      = aws_subnet.nsd.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "ceph" {
  subnet_id      = aws_subnet.ceph.id
  route_table_id = aws_route_table.main.id
}

output "vpc_id"         { value = aws_vpc.main.id }
output "subnet_k8s_id"  { value = aws_subnet.k8s.id }
output "subnet_nsd_id"  { value = aws_subnet.nsd.id }
output "subnet_ceph_id" { value = aws_subnet.ceph.id }
