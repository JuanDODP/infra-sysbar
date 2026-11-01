# IP elástica única: es la IP que se registra en DuckDNS
resource "aws_eip" "nlb" {
  domain = "vpc"

  tags = { Name = "${local.name_prefix}-nlb-eip" }
}

# NLB público con la IP elástica. Reenvía TCP 80/443 al ALB interno (pasa TLS sin tocarlo).
# Vive en una sola zona para tener una sola IP; el cross-zone le permite llegar
# a los nodos del ALB en las demás zonas.
resource "aws_lb" "nlb" {
  name                             = "${local.name_prefix}-nlb"
  internal                         = false
  load_balancer_type               = "network"
  security_groups                  = [aws_security_group.nlb_sg.id]
  enable_cross_zone_load_balancing = true

  subnet_mapping {
    subnet_id     = local.nlb_subnet_id
    allocation_id = aws_eip.nlb.id
  }

  tags = { Name = "${local.name_prefix}-nlb" }
}

# Target groups de tipo "alb": el destino del NLB es el propio ALB
resource "aws_lb_target_group" "nlb_to_alb" {
  for_each = local.nlb_ports

  name        = "${local.name_prefix}-nlb-${each.key}"
  port        = each.value
  protocol    = "TCP"
  target_type = "alb"
  vpc_id      = data.aws_vpc.default.id

  # Tiempo que el NLB tarda en soltar al ALB al desregistrarlo (por defecto 300 s)
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = each.key == "https" ? "HTTPS" : "HTTP"
    port                = "traffic-port"
    path                = var.health_check_path
    matcher             = "200-499" # el puerto 80 responde 301 (redirect a HTTPS)
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name_prefix}-nlb-${each.key}" }
}

# Al destruir: primero se quita el ALB del NLB, se esperan 60 s a que AWS lo suelte
# y después se borran los listeners del ALB (si no, AWS responde "ResourceInUse").
resource "time_sleep" "wait_nlb_deregistration" {
  destroy_duration = "60s"

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]
}

resource "aws_lb_target_group_attachment" "nlb_to_alb" {
  for_each = local.nlb_ports

  target_group_arn = aws_lb_target_group.nlb_to_alb[each.key].arn
  target_id        = aws_lb.alb.arn
  port             = each.value

  # El ALB debe tener el listener de ese puerto antes de registrarse en el NLB
  depends_on = [time_sleep.wait_nlb_deregistration]
}

resource "aws_lb_listener" "nlb" {
  for_each = local.nlb_ports

  load_balancer_arn = aws_lb.nlb.arn
  port              = each.value
  protocol          = "TCP"

  # Mantiene vivas las conexiones WebSocket inactivas (por defecto son 350 s)
  tcp_idle_timeout_seconds = var.lb_idle_timeout

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_to_alb[each.key].arn
  }
}
