# ALB interno: termina TLS y reparte el tráfico (HTTP y WebSockets) entre las instancias del ASG
resource "aws_lb" "alb" {
  name               = "${local.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = local.subnet_ids

  # Las conexiones WebSocket inactivas se cierran al cumplir este tiempo
  idle_timeout               = var.lb_idle_timeout
  drop_invalid_header_fields = true

  tags = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  # Tiempo para drenar conexiones (incluidas WebSockets) al sacar una instancia
  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Afinidad: el handshake de Socket.IO (polling -> upgrade) debe llegar al mismo servidor
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = var.enable_sticky_sessions
  }

  tags = { Name = "${local.name_prefix}-tg" }
}

# Las instancias las registra el Auto Scaling Group (asg.tf -> target_group_arns)

# HTTP -> HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS / WSS -> EC2
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.app.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
