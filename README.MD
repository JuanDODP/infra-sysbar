# 🚀 Guía de Despliegue de Infraestructura: INFRA-SYSBAR

Este repositorio contiene la automatización de la infraestructura en **AWS** utilizando **Terraform** para el aprovisionamiento de recursos y **Ansible** para la configuración del servidor web.

---

# 🛠️ Fase 1: Aprovisionamiento de Servicios en AWS (Terraform)

En esta fase se crean los siguientes recursos en AWS:

- 🖥️ Instancia **EC2**
- 🗄️ Base de datos **PostgreSQL** en **Amazon RDS**
- 🔒 Security Groups para EC2 y RDS

## 📋 Prerrequisitos

Antes de comenzar, asegúrate de contar con:

- **AWS CLI** instalado y configurado.

```bash
aws configure
```

- **Terraform** versión **1.0** o superior.
- Una **Key Pair** creada en AWS para el acceso SSH a la instancia EC2.

---

## ⚙️ Configuración de Variables

Las variables sensibles se almacenan en un archivo local `terraform.tfvars`, el cual no debe subirse al repositorio.

### 1. Crear el archivo de variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Completar los valores correspondientes a tu entorno

```hcl
aws_region  = "your-aws-region"
project     = "your-project-name"
environment = "dev"

key_name = "your-key-pair-name"

db_name     = "your_database_name"
db_user     = "your_database_user"
db_password = "your_secure_password"
```

> **Importante:** El archivo `terraform.tfvars` está excluido mediante `.gitignore` y debe permanecer únicamente en tu equipo.

---

## 🚀 Despliegue de la Infraestructura

Inicializa Terraform:

```bash
terraform init
```

Revisa el plan de ejecución:

```bash
terraform plan
```

Crea la infraestructura:

```bash
terraform apply -auto-approve
```

---

## 📤 Salida Esperada

Al finalizar el despliegue, Terraform mostrará información importante para los siguientes pasos.

Entre los valores más relevantes se encuentran:

- **EC2 Public IP**
- **RDS Endpoint**

Ejemplo:

```text
ec2_public_ip = XX.XX.XX.XX

rds_endpoint = your-database.xxxxxxxxxxxx.region.rds.amazonaws.com
```

---

# 🌐 Fase 2: Configuración del Dominio (DuckDNS)

Antes de configurar Nginx y los certificados SSL, el dominio debe apuntar a la dirección IP pública de la instancia EC2.

1. Inicia sesión en tu cuenta de **DuckDNS**.
2. Selecciona el subdominio que utilizarás.
3. Actualiza el registro con la **IPv4 pública** obtenida al finalizar el despliegue de Terraform.
4. Guarda los cambios.

> Espera unos minutos para que la propagación del DNS se complete antes de continuar.

---

# ⚙️ Fase 3: Configuración del Servidor (Ansible)

En esta fase se automatiza la configuración inicial del servidor, incluyendo:

- Instalación de dependencias.
- Instalación de Docker.
- Instalación y configuración de Nginx.
- Obtención automática de certificados SSL mediante Certbot.

## Preparar la Configuración

Desde la carpeta `ansible`, crea los archivos locales a partir de las plantillas de ejemplo:

```bash
cd ansible

cp inventory.ini.example inventory.ini
cp vars.yml.example vars.yml
```

Completa los valores necesarios según tu entorno antes de ejecutar el playbook.

> **Importante:** Los archivos `inventory.ini` y `vars.yml` contienen información específica de cada despliegue y no deben compartirse ni subirse al repositorio.

---

## Ejecutar el Playbook

Una vez configurados los archivos locales, ejecuta:

```bash
ansible-playbook -i inventory.ini deploy.yml
```

Al finalizar correctamente, el servidor quedará configurado con:

- ✅ Docker instalado.
- ✅ Nginx configurado.
- ✅ Certificados SSL generados automáticamente.
- ✅ Servidor listo para desplegar la aplicación.