aws_region = "eu-north-1"
vpc_cidr = "10.2.0.0/16"
instance_type = "t3.micro"


public_subnets = {
    "public1" = {
      cidr_block = "10.2.1.0/24"
      az = "eu-north-1a"
    }

    "public2" = {
      cidr_block = "10.2.3.0/24"
      az = "eu-north-1b"
    }
}

private_subnets = {
    "private1" = {
      cidr_block = "10.2.5.0/24"
      az = "eu-north-1a"
    }

    "private2" = {
      cidr_block = "10.2.7.0/24"
      az = "eu-north-1b"
    }
}

primary_security_group_ports = {
    ssh   = 22
    http  = 80
    app   = 3000
    app_v2 = 4000
}


launch_template_conf = {
    image_id = "ami-0aba19e56f3eaec05"
    instance_type = "t3.micro"
    key_name = "test1"
    script_name = "startup.sh"
}