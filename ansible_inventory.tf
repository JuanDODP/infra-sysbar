# Terraform escribe automáticamente los archivos que Ansible necesita,
# así no hay que copiar IPs ni endpoints a mano después de cada apply.

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/ansible/inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    hosts = [
      for i in aws_instance.app_server : {
        name       = i.tags["Name"]
        public_ip  = i.public_ip
        private_ip = i.private_ip
      }
    ]
    ssh_private_key_path = var.ssh_private_key_path
  })
}

# Contiene la contraseña de la BD: se escribe con permisos 0600 y está en .gitignore
resource "local_sensitive_file" "ansible_infra_vars" {
  filename        = "${path.module}/ansible/group_vars/all/infra.yml"
  file_permission = "0600"

  content = join("\n", [
    "# Generado por Terraform (ansible_inventory.tf). No editar a mano.",
    yamlencode({
      nlb_public_ip     = aws_eip.nlb.public_ip
      alb_dns_name      = aws_lb.alb.dns_name
      vpc_cidr          = data.aws_vpc.default.cidr_block
      rds_host          = aws_db_instance.postgres_rds.address
      rds_port          = aws_db_instance.postgres_rds.port
      db_name           = var.db_name
      db_user           = var.db_user
      db_password       = var.db_password
      redis_host        = var.enable_redis ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : ""
      redis_port        = 6379
      lb_idle_timeout   = var.lb_idle_timeout
      health_check_path = var.health_check_path
    }),
  ])
}
