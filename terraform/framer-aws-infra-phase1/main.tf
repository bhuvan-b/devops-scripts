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


resource "aws_subnet" "private" {
  for_each = var.private_subnets

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

// To assign to the NAT gateway
resource "aws_eip" "nat-gateway-eip" {
  domain   = "vpc"
}

// Nat Gateway

resource "aws_nat_gateway" "nat-gateway" {
  allocation_id = aws_eip.nat-gateway-eip.id
  subnet_id     = aws_subnet.public["public1"].id

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
  for_each = aws_subnet.private

  subnet_id      = each.value.id
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


# Create modules required for auto scaling group

# Create launch template

resource "aws_launch_template" "framer-pf-lt" {
  name = "framer-pf-launchTemplate"

  image_id = var.launch_template_conf.image_id
  instance_type = var.launch_template_conf.instance_type

  key_name = var.launch_template_conf.key_name
  update_default_version = true

  monitoring {
    enabled = true
  }

  # iam_instance_profile {
  #   name = aws_iam_instance_profile.ec2_cloudwatch_profile.name
  # }

  vpc_security_group_ids = [aws_security_group.framer-sg.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "framer-pf-launchTemplate-instance"
    }
  }

  user_data = filebase64("${path.module}/scripts/${var.launch_template_conf.script_name}")
}

# Create a target group

resource "aws_lb_target_group" "framer-pf-tg" {
  name        = "framer-pf-tg"
  target_type = "instance"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.framer-pf-vpc.id

  health_check {
    healthy_threshold = 2
    interval = 20
  }
}

# Create auto scaling group

resource "aws_autoscaling_group" "framer-pf-asg" {
  name = "framer-pf-asg"
  # availability_zones = ["eu-north-1a", "eu-north-1b"]
  desired_capacity   = 2
  max_size           = 4
  min_size           = 0

  vpc_zone_identifier = [for subnet in aws_subnet.private : subnet.id]
  target_group_arns = [aws_lb_target_group.framer-pf-tg.arn]

  launch_template {
    id      = aws_launch_template.framer-pf-lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Environment"
    value               = "Env-ASG-framer"
    propagate_at_launch = true
  }

  depends_on = [ aws_lb_target_group.framer-pf-tg ]
}

data "aws_instances" "asg_instances" {
  # Forces Terraform to wait until the ASG finishes initial creation
  depends_on = [aws_autoscaling_group.framer-pf-asg]

  instance_tags = {
    Environment = "Env-ASG-framer"
  }

  instance_state_names = ["running"]
}

output "asg_private_ips" {
  description = "Private IP addresses of the ASG instances"
  value       = data.aws_instances.asg_instances.private_ips
}

# # Create an application load balancer

# resource "aws_lb" "framer-pf-alb" {
#   name               = "framer-pf-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.framer-sg.id]
#   subnets            = [for subnet in aws_subnet.public : subnet.id]

#   tags = {
#     Environment = "production"
#   }
# }

# output "aws_alb_dns" {
#   value = aws_lb.framer-pf-alb.dns_name
  
# }

# resource "aws_lb_listener" "aws_lb_forward" {
#   load_balancer_arn = aws_lb.framer-pf-alb.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.framer-pf-tg.arn
#   }

#   depends_on = [ aws_lb_target_group.framer-pf-tg ]
# }

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

// Cloudwatch Related

# data "aws_iam_role" "cloudwatch-role" {
#   // Role for CloudWatch permissions - need to attach cloud watch policy
#   // This I already created in console, so just referencing it.
#   name = "instanceRole-temp1"
# }

# // This profile will be attached to the launch template
# resource "aws_iam_instance_profile" "ec2_cloudwatch_profile" {
#   name = "ec2-cloudwatch-profile"
#   role = data.aws_iam_role.cloudwatch-role.name
# }

# resource "aws_cloudwatch_log_group" "application-logs" {
#   name = "/framer-pf/ec2/application"

#   tags = {
#     Environment = "production"
#     Component = "application"
#   }
# }