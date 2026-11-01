# 1. Grupo de Seguridad para la RDS (PostgreSQL)
resource "aws_security_group" "rds_sg" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group para la RDS de PostgreSQL"
  vpc_id      = data.aws_vpc.default.id

  # Solo permite tráfico PostgreSQL (5432) desde el SG de las EC2 (las 3 instancias)
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id] # Conexión interna segura
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

# 2. Instancia RDS PostgreSQL (Capa Gratuita), compartida por todas las EC2
resource "aws_db_instance" "postgres_rds" {
  identifier            = "${local.name_prefix}-postgres"
  allocated_storage     = 20   # GB (Capa gratuita cubre hasta 20GB)
  max_allocated_storage = 20   # Desactiva auto-scaling para evitar cobros
  storage_type          = "gp2"
  engine                = "postgres"
  engine_version        = "15" # AWS seleccionará automáticamente la subversión 15.x más reciente
  instance_class        = "db.t4g.micro"

  db_name  = var.db_name
  username = var.db_user
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false # No accesible desde internet por seguridad
  skip_final_snapshot    = true  # Evita demoras al destruir en entorno dev

  tags = { Name = "${local.name_prefix}-postgres" }
}
