terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # Usando la generación v6 actual
    }

    # Genera el inventario y las variables de Ansible a partir de la infraestructura creada
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    # Pausa al destruir: espera a que el NLB suelte al ALB antes de borrar sus listeners
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile # perfil SSO de ~/.aws/config (null = usa AWS_PROFILE o credenciales por defecto)

  default_tags {
    tags = local.common_tags
  }
}
