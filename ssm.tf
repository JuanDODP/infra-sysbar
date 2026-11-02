# Configuración de la API guardada cifrada en SSM Parameter Store.
# Cada instancia nueva del Auto Scaling Group la lee al arrancar (y en cada deploy),
# así ningún secreto viaja en el user_data ni se guarda en la AMI.

resource "aws_ssm_parameter" "app_env" {
  name        = local.ssm_env_name
  description = "Contenido del .env de la API (${local.name_prefix})"
  type        = "SecureString"
  value       = local.app_env

  tags = { Name = "${local.name_prefix}-app-env" }
}

# Deploy key de solo lectura para clonar el repo privado de la API
resource "aws_ssm_parameter" "deploy_key" {
  count = local.use_deploy_key ? 1 : 0

  name        = local.ssm_key_name
  description = "Deploy key (solo lectura) del repositorio de la API"
  type        = "SecureString"
  value       = file(pathexpand(var.github_deploy_key_path))

  tags = { Name = "${local.name_prefix}-deploy-key" }
}
