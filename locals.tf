locals {
  # Prefijo dinámico para nombrar recursos: ej. "sysranchito-dev"
  name_prefix = "${var.project}-${var.environment}"

  # Etiquetas estandarizadas que se aplicarán a todos los recursos de AWS
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # Subnets por defecto ordenadas por zona. us-east-1 tiene 6 zonas (a-f); se usan
  # las primeras var.az_count (a, b, c). Así se evita us-east-1e, que no ofrece t3.
  subnet_ids_by_az = { for s in data.aws_subnet.default : s.availability_zone => s.id }
  all_azs          = sort(keys(local.subnet_ids_by_az))
  azs              = slice(local.all_azs, 0, min(var.az_count, length(local.all_azs)))
  subnet_ids       = [for az in local.azs : local.subnet_ids_by_az[az]]

  # El NLB vive en una sola zona para tener UNA sola IP elástica
  nlb_subnet_id = local.subnet_ids[0]

  # Puertos que el NLB reenvía al ALB
  nlb_ports = {
    http  = 80
    https = 443
  }

  # Archivos del certificado generados por ansible/certificado.yml
  cert_dir = "${path.module}/${var.tls_cert_dir}"

  # Parámetros de SSM que lee cada instancia al arrancar
  ssm_prefix     = "/${local.name_prefix}/app"
  ssm_env_name   = "${local.ssm_prefix}/env"
  ssm_key_name   = "${local.ssm_prefix}/deploy_key"
  use_deploy_key = var.github_deploy_key_path != ""

  redis_host = var.enable_redis ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : ""

  # Contenido del .env de la API (se guarda cifrado en SSM, nunca en el user_data)
  app_env = join("\n", concat(
    [
      "PORT=${var.app_port}",
      "DB_HOST=${aws_db_instance.postgres_rds.address}",
      "DB_PORT=${aws_db_instance.postgres_rds.port}",
      "DB_NAME=${var.db_name}",
      "DB_USERNAME=${var.db_user}",
      "DB_PASSWORD=${var.db_password}",
      "REDIS_HOST=${local.redis_host}",
      "REDIS_PORT=6379",
      "REDIS_URL=${local.redis_host != "" ? "redis://${local.redis_host}:6379" : ""}",
    ],
    [for k, v in var.app_extra_env : "${k}=${v}"],
  ))
}
