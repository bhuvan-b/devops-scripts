variable "aws_region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "public_subnets" {
  type = map(object({
    cidr_block = string
    az   = string
  }))
}

variable "private_subnets" {
  type = map(object({
    cidr_block = string
    az   = string
  }))
}

variable "primary_security_group_ports" {
  type = map(number)

  default = {
    ssh   = 22
    http  = 80
  }
}

variable "launch_template_conf" {
  type = map(string)
}