# 1. Grupo de Seguridad
resource "aws_security_group" "ec2_sg" {
  name        = "${local.name_prefix}-sg"
  description = "Security Group para API NestJS en ${var.environment}"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP (Nginx / Certbot)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Puerto 3000 (NestJS API)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Salida libre a Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-sg"
    }
  )
}

# 2. Instancia EC2 (Capa Gratuita)
resource "aws_instance" "app_server" {
  ami           = "ami-0ea1cddefe0c4aed5" # Ubuntu Server 24.04 LTS en us-east-2
  instance_type = "t3.micro"
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-ec2"
    }
  )
}

# 3. Outputs
output "ec2_public_ip" {
  description = "IP Pública asignada a la EC2"
  value       = aws_instance.app_server.public_ip
}