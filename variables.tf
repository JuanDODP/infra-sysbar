# ==========================================
# GENERALES
# ==========================================
variable "aws_region" {
  description = "Región de AWS donde se desplegará la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI a usar (ej. el perfil creado con aws configure sso). null = AWS_PROFILE / credenciales por defecto"
  type        = string
  default     = null
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

variable "domain_name" {
  description = "Dominio público de la aplicación (DuckDNS), ej. mi-app.duckdns.org"
  type        = string
}

# ==========================================
# EC2 (servidores de la aplicación)
# ==========================================
variable "instance_count" {
  description = "Número de instancias EC2 detrás del balanceador"
  type        = number
  default     = 3

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "instance_count debe estar entre 1 y 10."
  }
}

variable "instance_type" {
  description = "Tipo de instancia EC2 (t3.micro: la mínima viable para Docker + NestJS; t3.nano se queda sin RAM)"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI fija opcional. Vacío = Ubuntu Server 24.04 LTS oficial más reciente de la región"
  type        = string
  default     = ""
}

variable "az_count" {
  description = "Cuántas zonas de disponibilidad usar (EC2, ALB, Redis). El ALB necesita mínimo 2"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count debe ser al menos 2 (requisito del ALB)."
  }
}

variable "root_volume_size" {
  description = "Tamaño del disco raíz en GB (las imágenes de Docker ocupan espacio)"
  type        = number
  default     = 16
}

variable "key_name" {
  description = "Nombre del Key Pair de EC2 (en la misma región) para SSH, sin .pem"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Ruta local a la llave privada .pem (se escribe en el inventario de Ansible)"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs que pueden entrar por SSH a las EC2. Usa tu IP pública con /32"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ==========================================
# BALANCEADORES
# ==========================================
variable "lb_idle_timeout" {
  description = "Segundos que una conexión inactiva (WebSocket) se mantiene abierta en NLB y ALB"
  type        = number
  default     = 3600

  validation {
    condition     = var.lb_idle_timeout >= 60 && var.lb_idle_timeout <= 4000
    error_message = "lb_idle_timeout debe estar entre 60 y 4000 segundos (límite del ALB)."
  }
}

variable "health_check_path" {
  description = "Ruta que el ALB consulta para saber si una instancia está sana"
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "Códigos HTTP que se consideran sanos. Si agregas /health en NestJS, cámbialo a \"200\""
  type        = string
  default     = "200-499"
}

variable "enable_sticky_sessions" {
  description = "Cookie de afinidad del ALB (necesaria si Socket.IO usa long-polling antes de WebSocket)"
  type        = bool
  default     = true
}

variable "tls_cert_dir" {
  description = "Carpeta (relativa al proyecto) con cert.pem, privkey.pem y chain.pem generados por ansible/certificado.yml"
  type        = string
  default     = "certs"
}

# ==========================================
# REDIS (sincroniza WebSockets entre servidores)
# ==========================================
variable "enable_redis" {
  description = "Crea un ElastiCache Redis para el adaptador de Socket.IO entre las instancias"
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "Tipo de nodo de ElastiCache"
  type        = string
  default     = "cache.t4g.micro" # el nodo más pequeño/barato de ElastiCache
}

# ==========================================
# BASE DE DATOS
# ==========================================
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
