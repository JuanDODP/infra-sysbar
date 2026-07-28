variable "aws_region" {
  description = "Región de AWS donde se desplegará la infraestructura"
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Nombre del proyecto"
  type        = string
  default     = "sysranchito"
}

variable "environment" {
  description = "Entorno de despliegue (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "key_name" {
  description = "Nombre del Key Pair en AWS para SSH"
  type        = string
  default     = "PEMTEST"
}
##VAriables para la base de datos
variable "db_name" {
  description = "Nombre de la base de datos PostgreSQL"
  type        = string
  default     = "sysranchitodb"
}

variable "db_user" {
  description = "Usuario administrador de la base de datos"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Contraseña de la base de datos"
  type        = string
  sensitive   = true # Evita que se imprima la contraseña en logs
}