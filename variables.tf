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
# ==========================================
# AUTO SCALING GROUP (cuántos servidores y cuándo crecer)
# ==========================================
variable "asg_min_size" {
  description = "Mínimo de instancias: nunca habrá menos (cuando el tráfico baja al mínimo)"
  type        = number
  default     = 1

  validation {
    condition     = var.asg_min_size >= 1
    error_message = "asg_min_size debe ser al menos 1."
  }
}

variable "asg_desired_capacity" {
  description = "Instancias recomendadas al crear el grupo. Después las ajustan las políticas de escalado"
  type        = number
  default     = 3

  validation {
    condition     = var.asg_desired_capacity >= var.asg_min_size && var.asg_desired_capacity <= var.asg_max_size
    error_message = "asg_desired_capacity debe estar entre asg_min_size y asg_max_size."
  }
}

variable "asg_max_size" {
  description = "Máximo de instancias cuando el tráfico es máximo"
  type        = number
  default     = 10

  validation {
    condition     = var.asg_max_size >= var.asg_min_size && var.asg_max_size <= 20
    error_message = "asg_max_size debe ser >= asg_min_size y <= 20."
  }
}

variable "scaling_cpu_target" {
  description = "CPU promedio (%) que el grupo intenta mantener: si sube, agrega instancias; si baja, quita"
  type        = number
  default     = 60
}

variable "scaling_requests_per_target" {
  description = "Peticiones por minuto por instancia que el grupo intenta mantener (segunda señal de escalado)"
  type        = number
  default     = 1000
}

variable "instance_warmup" {
  description = "Segundos que tarda una instancia nueva en estar lista (bootstrap + docker build en t3.micro)"
  type        = number
  default     = 600
}

variable "health_check_grace_period" {
  description = "Segundos que el ASG espera antes de juzgar la salud de una instancia nueva"
  type        = number
  default     = 900
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
  description = "Ruta local a la llave privada .pem (la usa Ansible para conectarse por SSH)"
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
# APLICACIÓN (la despliega cada instancia al arrancar)
# ==========================================
variable "app_repo_url" {
  description = "Repositorio de la API. Privado: SSH (git@github.com:USUARIO/REPO.git) + deploy key. Público: https"
  type        = string
}

variable "app_repo_version" {
  description = "Rama que se despliega"
  type        = string
  default     = "main"
}

variable "app_compose_file" {
  description = "Archivo docker compose de producción dentro del repo de la API"
  type        = string
  default     = "docker-compose.prod.yml"
}

variable "app_port" {
  description = "Puerto donde escucha la API dentro de cada instancia (Nginx le reenvía el tráfico)"
  type        = number
  default     = 3000
}

variable "app_extra_env" {
  description = "Variables extra para el .env de la API (JWT_SECRET, NODE_ENV, etc.). Se guardan cifradas en SSM"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "github_deploy_key_path" {
  description = "Ruta local a la deploy key (solo lectura) para clonar un repo privado. Vacío = repo público"
  type        = string
  default     = ""
}

variable "nginx_client_max_body_size" {
  description = "Tamaño máximo de subida que acepta Nginx"
  type        = string
  default     = "10m"
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
