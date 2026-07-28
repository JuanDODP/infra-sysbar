locals {
  # Prefijo dinámico para nombrar recursos: ej. "sysranchito-dev"
  name_prefix = "${var.project}-${var.environment}"

  # Etiquetas estandarizadas que se aplicarán a todos los recursos de AWS
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}