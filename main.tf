terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

variable "subnet_prefix" {
  description = "cidr block for the subnet"
}

variable "access_key" {
  description = "aws access key"
  type        = string
}

variable "secret_key" {
  description = "aws secret key"
  type        = string
}

# Configuration du provider AWS
provider "aws" {
  region = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

# 1 _ Création d'un VPC de production
resource "aws_vpc" "prod_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

# 2 _ Création d'une Internet Gateway "gw"
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod_vpc.id

  tags = {
    Name = "main"
  }
}

# 3 _ Création d'une table de routage pour rediriger le traffic vers "gw"
resource "aws_route_table" "prod_route_table" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0" # route pour rediriger tout le traffic IP V4 vers l'internet gateway "gw" définie plus haut
    gateway_id = aws_internet_gateway.gw.id
  }

  # route optionnele, pour gérer le traffic IPV6
  route {
    ipv6_cidr_block        = "::/0"
    gateway_id             = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}

# 4 _ Création d'un subnet de production
resource "aws_subnet" "subnet_1" {
  vpc_id     = aws_vpc.prod_vpc.id
  cidr_block = var.subnet_prefix[0]
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet"
  }
}

# 4bis _ Création d'un deuxième subnet
resource "aws_subnet" "subnet_2" {
  vpc_id     = aws_vpc.prod_vpc.id
  cidr_block = var.subnet_prefix[1]
  availability_zone = "us-east-1a"

  tags = {
    Name = "dev-subnet"
  }
}

# 5 _ Création d'une association entre le subnet de prod et la table de routage de prod
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.prod_route_table.id
}

# 6 _ Création d'un groupe de sécurité pour autoriser toutes les connexion HTTPS, HTTP et SSH depuis le web
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress { // c'est quoi ca ?
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow web"
  }
}

# 7 _ Création d'une interface réseau
resource "aws_network_interface" "web_server_max" { // c'est quoi ça ?
  subnet_id       = aws_subnet.subnet_1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# 8 _ Création d'une elastic IP
# /!\ L'elastic IP à besoin d'une internet gateway déployée pour fonctionner:
# Si on créée une eip qui pointe vers un appareil dans un subnet ou un VPC qui n'a pas d'internet gateway, il retournera une erreur
# car pour avoir une IP publique, on a besoin d'une internet gateway
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web_server_max.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}

# 9 _ Création d'un serveur ubuntu
resource "aws_instance" "web-server-instance" {
  ami = "ami-09cd747c78a9add63"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "main-key"
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web_server_max.id
  }
  # permet de lancer une commande dans le serveur ubuntu
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c "echo your very first web server > /var/www/html/index.html"
              EOF
  tags = {
    Name = "web-server"
  }
}

output "server_private_ip" {
  value = aws_instance.web-server-instance.private_ip
}

output "server_id" {
  value = aws_instance.web-server-instance.id
}