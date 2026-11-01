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
}
