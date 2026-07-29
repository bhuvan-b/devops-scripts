# Create a VPC
resource "aws_vpc" "framer-pf-vpc" {
  cidr_block = "10.2.0.0/16"

  tags = {
    Name = "framer-pf-vpc"
  }
}

resource "aws_subnet" "public1" {
  vpc_id     = aws_vpc.framer-pf-vpc.id
  cidr_block = "10.2.1.0/24"
  availability_zone = "eu-north-1a"

  tags = {
    Name = "framer-pf-public1"
  }
}

resource "aws_subnet" "public2" {
  vpc_id     = aws_vpc.framer-pf-vpc.id
  cidr_block = "10.2.3.0/24"
  availability_zone = "eu-north-1b"

  tags = {
    Name = "framer-pf-public2"
  }
}

resource "aws_subnet" "private1" {
  vpc_id     = aws_vpc.framer-pf-vpc.id
  cidr_block = "10.2.5.0/24"
  availability_zone = "eu-north-1a"

  tags = {
    Name = "framer-pf-private1"
  }
}

resource "aws_subnet" "private2" {
  vpc_id     = aws_vpc.framer-pf-vpc.id
  cidr_block = "10.2.7.0/24"
  availability_zone = "eu-north-1b"

  tags = {
    Name = "framer-pf-private2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.framer-pf-vpc.id

  tags = {
    Name = "framer-pf-igw"
  }
}

resource "aws_default_route_table" "main-rtb" {
  default_route_table_id = aws_vpc.framer-pf-vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "framer-pf-main-route-table"
  }
}

// To assign to the NAT gateway
resource "aws_eip" "nat-gateway-eip" {
  domain   = "vpc"
}

// Nat Gateway

resource "aws_nat_gateway" "nat-gateway" {
  allocation_id = aws_eip.nat-gateway-eip.id
  subnet_id     = aws_subnet.public1.id

  tags = {
    Name = "framer-pf-nat-gateway"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.igw]
}

// Create Pvt Route Table

resource "aws_route_table" "private-rtb" {
  vpc_id = aws_vpc.framer-pf-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat-gateway.id
  }

  tags = {
    Name = "framer-pf-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  for_each = {
    subnet1 = aws_subnet.private1.id
    subnet2 = aws_subnet.private2.id
  }

  subnet_id      = each.value
  route_table_id = aws_route_table.private-rtb.id
}

// VPC Security Group

resource "aws_security_group" "framer-sg" {
  name        = "framer-pf-sg-all"
  description = "General security group, with selective inbound traffic, and all outbound traffic allowed"
  vpc_id      = aws_vpc.framer-pf-vpc.id

  tags = {
    Name = "framer-pf-sg-all"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.framer-sg.id

  for_each = {
    port1 = 80
    port2 = 3000
    port3 = 22
  }

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port = each.value
  to_port = each.value

}