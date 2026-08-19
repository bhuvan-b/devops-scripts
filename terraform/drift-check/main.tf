# Create a VPC
resource "aws_vpc" "framer-pf-vpc" {
  cidr_block = "10.2.0.0/16"

  tags = {
    Name = "framer-pf-vpc"
  }
}

resource "aws_subnet" "public" {

  for_each = var.public_subnets  

  vpc_id     = aws_vpc.framer-pf-vpc.id
  cidr_block = each.value.cidr_block
  availability_zone = each.value.az

  tags = {
    Name = "framer-pf-${each.key}"
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
  for_each = var.primary_security_group_ports

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port = each.value
  to_port = each.value

}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.framer-sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}


# Create a jump host in public subnet to access instances in private subnet

# resource "aws_eip" "jumphost-eip" {
#   domain   = "vpc"
# }

resource "aws_instance" "jump_host" {
  ami           = var.launch_template_conf.image_id
  instance_type = var.launch_template_conf.instance_type
  subnet_id = aws_subnet.public["public1"].id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.framer-sg.id]
  key_name = var.launch_template_conf.key_name

  tags = {
    Name = "framer-pf-jumphost"
  }
}

output "jump_host_public_ip" {
  description = "Public IP address of the jump host"
  value = aws_instance.jump_host.public_ip
}
