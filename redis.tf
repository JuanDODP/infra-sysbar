# Redis compartido para el adaptador de Socket.IO.
# Sin esto, un evento emitido en la EC2-1 no llega a los clientes conectados a la EC2-2 o EC2-3.

resource "aws_security_group" "redis_sg" {
  count = var.enable_redis ? 1 : 0

  name        = "${local.name_prefix}-redis-sg"
  description = "Redis solo accesible desde las EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Redis desde las EC2"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-redis-sg" }
}

resource "aws_elasticache_subnet_group" "redis" {
  count = var.enable_redis ? 1 : 0

  name       = "${local.name_prefix}-redis-subnets"
  subnet_ids = local.subnet_ids
}

resource "aws_elasticache_cluster" "redis" {
  count = var.enable_redis ? 1 : 0

  cluster_id           = "${local.name_prefix}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  availability_zone    = local.azs[0]
  subnet_group_name    = aws_elasticache_subnet_group.redis[0].name
  security_group_ids   = [aws_security_group.redis_sg[0].id]

  tags = { Name = "${local.name_prefix}-redis" }
}
