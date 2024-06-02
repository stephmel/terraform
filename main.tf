terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region     = "eu-central-1"
  shared_credentials_files = ["~/.aws/creds"]
}

#1 Create vpc
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

#2 create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

#3 create custom route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id
  route {
    #allow everything
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "prod-route"
  }
}

#4 create a subnet
variable "subnet_prefix" {
  description = "cidr block for subnet"
  default = "10.0.1.0/24"
  # type = list(string), number, object, any
}

resource "aws_subnet" "subnet-prod" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = var.subnet_prefix[0].cidr_block
  availability_zone = "eu-central-1b"
  tags = {
    Name = var.subnet_prefix[0].name
  }
}

resource "aws_subnet" "subnet-dev" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = var.subnet_prefix[1].cidr_block
  availability_zone = "eu-central-1b"
  tags = {
    Name = var.subnet_prefix[1].name
  }
}

#5 associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-prod.id
  route_table_id = aws_route_table.prod-route-table.id
}

#6 create security group to allow port 22(ssh), 80(HTTP), 443(HTTPS)
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allows web traffic from cidr_blocks"
  vpc_id      = aws_vpc.prod-vpc.id
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol = "tcp"
    # only my ip
    cidr_blocks = ["88.130.149.98/32"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["88.130.149.98/32"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["88.130.149.98/32"]
  }
  egress {
    from_port   = 0
    to_port = 0
    # any protocol
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow web access"
  }
}

#7 Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-prod.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

#8 Assign an elastic IP to the network interfact created in step 7
resource "aws_eip" "server-eip" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.server-eip.public_ip
}

#9 Create Ubuntu server and install/enable Apache2
resource "aws_instance" "ubuntu-server" {
  availability_zone = "eu-central-1b"
  ami               = "ami-01e444924a2233b07"
  instance_type     = "t2.micro"
  key_name          = "terraform"
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install apache2 -y
    sudo systemctl start apache2
    sudo bash -c "echo welcome to my web server! > /var/www/html/index.html"
    EOF
  tags = {
    Name = "web-server"
  }
}

output "server_private_ip" {
  value = aws_instance.ubuntu-server.private_ip
}
