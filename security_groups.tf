# Flujo del tráfico:
# Internet -> NLB (IP elástica) -> ALB interno -> EC2 (Nginx :80) -> NestJS (:3000)

# 1. NLB: único punto público de entrada
resource "aws_security_group" "nlb_sg" {
  name        = "${local.name_prefix}-nlb-sg"
  description = "NLB publico con IP elastica"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP (redirige a HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS y WebSockets (wss)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-nlb-sg" }
}

# 2. ALB interno: no tiene IP pública. El NLB conserva la IP real del cliente,
#    por eso se permite 0.0.0.0/0 (solo es alcanzable desde dentro de la VPC).
resource "aws_security_group" "alb_sg" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB interno detras del NLB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP desde el NLB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS desde el NLB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

# 3. EC2: solo reciben HTTP del ALB y SSH desde las IPs permitidas
resource "aws_security_group" "ec2_sg" {
  name        = "${local.name_prefix}-sg"
  description = "Security Group para API NestJS en ${var.environment}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (Ansible)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  ingress {
    description     = "HTTP solo desde el ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "Salida libre a Internet (apt, Docker, git)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg" }
}
