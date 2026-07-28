terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # Usando la generación v6 actual
    }
  }
}

provider "aws" {
  region = var.aws_region
}