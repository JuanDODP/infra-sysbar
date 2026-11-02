# =============================================================================
# Auto Scaling Group: los servidores de la API ya no son fijos.
#   mínimo 1  ·  recomendado (deseado) 3  ·  máximo 10
# Cada instancia nueva se configura y despliega sola con el bootstrap (user_data).
# =============================================================================

# Molde de cada instancia: AMI, tamaño, red, disco, rol y script de arranque
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-app-"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  network_interfaces {
    associate_public_ip_address = true # salida a Internet (apt, Docker, GitHub) y SSH para Ansible
    security_groups             = [aws_security_group.ec2_sg.id]
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region               = var.aws_region
    env_param            = aws_ssm_parameter.app_env.name
    key_param            = local.use_deploy_key ? aws_ssm_parameter.deploy_key[0].name : ""
    repo_url             = var.app_repo_url
    branch               = var.app_repo_version
    compose_file         = var.app_compose_file
    app_port             = var.app_port
    domain_name          = var.domain_name
    vpc_cidr             = data.aws_vpc.default.cidr_block
    idle_timeout         = var.lb_idle_timeout
    client_max_body_size = var.nginx_client_max_body_size
  }))

  # Las etiquetas de las instancias las pone el ASG (propagate_at_launch)
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-app" })
  }

  tags = { Name = "${local.name_prefix}-app-lt" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = local.subnet_ids # reparte las instancias entre us-east-1a, 1b y 1c

  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity
  max_size         = var.asg_max_size

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # El ASG registra/desregistra solo las instancias en el target group del ALB
  target_group_arns = [aws_lb_target_group.app.arn]

  # Si el ALB marca una instancia como no sana, el ASG la reemplaza
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = var.instance_warmup

  # No bloquear `terraform apply` mientras las instancias construyen la imagen (~8 min)
  wait_for_capacity_timeout = "0"

  # Al cambiar el launch template (AMI, tamaño, bootstrap...) reemplaza las instancias
  # sin cortar el servicio: primero lanza las nuevas y luego retira las viejas.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = var.instance_warmup
      skip_matching          = true
    }
  }

  enabled_metrics = [
    "GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity",
    "GroupInServiceInstances", "GroupPendingInstances", "GroupTerminatingInstances",
  ]

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "app"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # Los parámetros deben existir antes de que arranque la primera instancia
  depends_on = [
    aws_ssm_parameter.app_env,
    aws_ssm_parameter.deploy_key,
    aws_iam_role_policy.app_ssm_read,
  ]

  lifecycle {
    # Las políticas de escalado cambian desired_capacity; Terraform no debe regresarlo a 3
    ignore_changes = [desired_capacity]
  }
}

# -----------------------------------------------------------------------------
# Políticas de escalado (target tracking): AWS agrega instancias cuando una señal
# sube por encima del objetivo y las quita cuando baja (sin pasar del mínimo/máximo).
# Con dos políticas: escala hacia arriba si CUALQUIERA lo pide y hacia abajo solo
# si AMBAS lo permiten.
# -----------------------------------------------------------------------------
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${local.name_prefix}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.scaling_cpu_target
  }
}

# AWS tarda unos segundos en reconocer que el target group pertenece al ASG; si la
# política de peticiones se crea antes, responde "Provided Target Groups may not be valid".
resource "time_sleep" "wait_asg_target_group" {
  create_duration = "30s"

  depends_on = [aws_autoscaling_group.app, aws_lb_listener.https]
}

resource "aws_autoscaling_policy" "requests" {
  name                   = "${local.name_prefix}-requests-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.alb.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = var.scaling_requests_per_target
  }

  # El target group debe estar asociado al ASG y a un listener del ALB
  depends_on = [time_sleep.wait_asg_target_group]
}
