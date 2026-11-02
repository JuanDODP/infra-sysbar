# Terraform escribe los datos que necesita Ansible. Las instancias ya no son fijas
# (las crea y destruye el Auto Scaling Group), así que el inventario es dinámico:
# ansible/inventory.py consulta a AWS en cada ejecución qué instancias están vivas.

# Configuración del inventario dinámico (sin secretos)
resource "local_file" "ansible_aws_inventory" {
  filename        = "${path.module}/ansible/.aws_inventory.json"
  file_permission = "0644"

  content = jsonencode({
    region               = var.aws_region
    profile              = var.aws_profile
    asg_name             = aws_autoscaling_group.app.name
    ssh_user             = "ubuntu"
    ssh_private_key_path = var.ssh_private_key_path
  })
}

# Variables de la infraestructura para los playbooks (sin secretos: el .env vive en SSM)
resource "local_file" "ansible_infra_vars" {
  filename        = "${path.module}/ansible/group_vars/all/infra.yml"
  file_permission = "0644"

  content = join("\n", [
    "# Generado por Terraform (ansible_inventory.tf). No editar a mano.",
    yamlencode({
      nlb_public_ip     = aws_eip.nlb.public_ip
      alb_dns_name      = aws_lb.alb.dns_name
      asg_name          = aws_autoscaling_group.app.name
      aws_region        = var.aws_region
      aws_profile       = var.aws_profile
      app_port          = var.app_port
      health_check_path = var.health_check_path
    }),
  ])
}
