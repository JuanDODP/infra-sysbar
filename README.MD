# 🚀 INFRA-SYSBAR — Infraestructura multi-servidor en AWS

Este repositorio crea y configura, con unos pocos comandos, todo lo necesario para publicar una **API NestJS con WebSockets** en internet, repartida en **3 servidores** para que sea más estable, con **HTTPS** y un **dominio gratuito de DuckDNS**.

- **Terraform** crea la infraestructura en AWS (servidores, balanceadores, base de datos…).
- **Ansible** configura los servidores y despliega la aplicación.

> 💡 **En palabras simples:** en lugar de tener tu aplicación en una sola computadora (si se cae, se cae todo), la tienes en 3 computadoras. Un "recepcionista" (el balanceador) recibe a cada visitante y lo manda a la computadora que esté libre. Si una falla, el recepcionista deja de mandarle gente y las otras dos siguen atendiendo.

---

## 📑 Índice

1. [Arquitectura](#-arquitectura)
2. [Glosario rápido](#-glosario-rápido)
3. [Estructura del repositorio](#-estructura-del-repositorio)
4. [Requisitos](#-requisitos)
5. [Configuración: archivos `.example`](#%EF%B8%8F-configuración-archivos-example)
6. [Despliegue paso a paso](#-despliegue-paso-a-paso)
7. [Requisitos de la aplicación (API)](#-requisitos-de-la-aplicación-api)
8. [Verificar que todo funciona](#-verificar-que-todo-funciona)
9. [Operación del día a día](#-operación-del-día-a-día)
10. [Apagar y volver a encender](#-apagar-y-volver-a-encender)
11. [Solución de problemas](#-solución-de-problemas)
12. [Costos](#-costos)
13. [Seguridad](#-seguridad)
14. [Limitaciones y mejoras futuras](#-limitaciones-y-mejoras-futuras)

---

## 🗺️ Arquitectura

```text
                        tu-subdominio.duckdns.org
                                    │  (registro A → IP elástica)
                                    ▼
                     ┌──────────────────────────────┐
     Internet ─────▶ │ NLB público + 1 IP elástica  │  TCP 80 / 443 (no toca el TLS)
                     └──────────────┬───────────────┘
                                    ▼
                     ┌──────────────────────────────┐
                     │ ALB interno                  │  Termina HTTPS (certificado Let's Encrypt en ACM)
                     │  80  → redirige a 443        │  Timeout de 3600 s para WebSockets
                     │  443 → Target Group          │  Health check: GET /api/health
                     └──────┬──────────┬────────┬───┘
                            ▼          ▼        ▼
                        EC2-1 (a)   EC2-2 (b)  EC2-3 (c)    Nginx :80 → API :3000 (Docker)
                            │          │        │
                            ├──────────┴────────┤
                            ▼                   ▼
                   RDS PostgreSQL        ElastiCache Redis
                   (compartida)          (sincroniza Socket.IO entre servidores)
```

| Pieza | Qué hace (simple) | Detalle técnico |
|---|---|---|
| **DuckDNS** | El "nombre" de tu sitio | Registro A apuntando a la IP elástica del NLB |
| **NLB** (Network Load Balancer) | La puerta de entrada con una **dirección fija** | Única IP pública estable; reenvía TCP 80/443 al ALB, en una sola zona |
| **ALB** (Application Load Balancer) | El recepcionista que reparte a los visitantes | Interno; termina TLS, health checks, *sticky sessions*, idle timeout de 3600 s |
| **3 × EC2** | Las 3 computadoras donde corre tu API | Ubuntu 24.04, `t3.micro`, una por zona (a, b, c); Nginx → contenedor Docker |
| **RDS PostgreSQL** | La base de datos que comparten las 3 | `db.t4g.micro`, privada, solo accesible desde las EC2 |
| **ElastiCache Redis** | El "chat interno" entre servidores | Adaptador de Socket.IO: un evento emitido en un servidor llega a los clientes de los otros |
| **ACM** | Guarda el candado HTTPS | Certificado de Let's Encrypt importado (ACM no emite para `duckdns.org`) |

**¿Por qué NLB + ALB y no solo ALB?** Un ALB **no puede tener IP fija**, y DuckDNS **solo acepta IPs** (no permite apuntar a un nombre/CNAME). El NLB aporta la IP fija; el ALB aporta el reparto inteligente HTTP/WebSocket y el HTTPS.

**¿Por qué Redis?** Con WebSockets, cada usuario queda conectado a **un** servidor. Si la caja está en el servidor 1 y la cocina en el servidor 2, sin Redis la cocina nunca se enteraría de la orden. Redis comparte los eventos entre los 3.

---

## 📖 Glosario rápido

| Término | Significado |
|---|---|
| **AWS** | Amazon Web Services: la nube donde se rentan los servidores |
| **Región** | Ubicación física de AWS. Este proyecto usa `us-east-1` (Norte de Virginia) |
| **EC2** | Un servidor virtual (una computadora en la nube) |
| **Key Pair / `.pem`** | La "llave" para entrar por SSH a los servidores. Es por región |
| **Security Group** | Firewall de AWS: decide quién puede conectarse a qué puerto |
| **IP elástica** | IP pública fija que no cambia aunque reinicies recursos |
| **Terraform** | Herramienta que crea infraestructura a partir de archivos `.tf` |
| **`terraform.tfstate`** | "Memoria" de Terraform: qué creó. Contiene datos sensibles |
| **Ansible** | Herramienta que se conecta por SSH y configura servidores con *playbooks* (`.yml`) |
| **Health check** | Revisión periódica: si un servidor no responde 200, deja de recibir tráfico |
| **Let's Encrypt** | Autoridad que emite certificados HTTPS gratuitos (duran 90 días) |
| **Rolling deploy** | Actualizar los servidores uno por uno, sin apagar el servicio |

---

## 📁 Estructura del repositorio

```text
infra-sysbar/
├── provider.tf               # Proveedores (aws, local, time) y perfil de AWS
├── variables.tf              # Todas las variables configurables (con descripción)
├── locals.tf                 # Valores calculados (nombres, zonas, subnets)
├── network.tf                # VPC por defecto, subnets y AMI de Ubuntu 24.04
├── security_groups.tf        # Firewalls de NLB, ALB y EC2
├── main.tf                   # Las instancias EC2
├── alb.tf                    # ALB interno, target group y listeners 80/443
├── nlb.tf                    # IP elástica, NLB y conexión NLB → ALB
├── certificate.tf            # Importa el certificado de certs/ a ACM
├── rds.tf                    # PostgreSQL
├── redis.tf                  # ElastiCache Redis
├── ansible_inventory.tf      # Genera el inventario y variables para Ansible
├── outputs.tf                # Datos que muestra Terraform al terminar
├── templates/
│   └── inventory.ini.tftpl   # Plantilla del inventario de Ansible
├── terraform.tfvars.example  # 📝 PLANTILLA → copiar a terraform.tfvars
├── ansible/
│   ├── ansible.cfg           # Configuración de Ansible (SSH estable)
│   ├── certificado.yml       # Paso 1: certificado HTTPS (corre en tu computadora)
│   ├── duckdns.yml           # Paso 3: apunta el dominio a la IP elástica
│   ├── deploy.yml            # Paso 4: configura servidores y despliega la API
│   ├── nginx.conf.j2         # Nginx con soporte WebSocket
│   ├── app.env.j2            # Plantilla del .env de la API
│   ├── vars.yml.example      # 📝 PLANTILLA → copiar a vars.yml
│   └── inventory.ini.example # Solo referencia (el real lo genera Terraform)
└── scripts/
    ├── package.json
    └── test-websockets.mjs   # Prueba de WebSockets entre servidores
```

**Archivos que se generan solos y NUNCA se suben a git** (ya están en `.gitignore`):

| Archivo | Lo crea | Contiene |
|---|---|---|
| `terraform.tfvars` | Tú (desde el `.example`) | Tu configuración y contraseña de la BD |
| `ansible/vars.yml` | Tú (desde el `.example`) | Token de DuckDNS, secretos de la app |
| `certs/` | `certificado.yml` | Certificado y **llave privada** HTTPS |
| `ansible/inventory.ini` | Terraform | IPs públicas de los servidores |
| `ansible/group_vars/all/infra.yml` | Terraform | Endpoints de RDS/Redis y contraseña de la BD |
| `terraform.tfstate*` | Terraform | Estado completo (incluye secretos) |

---

## 📋 Requisitos

### Cuentas

- **AWS** con permisos de administrador (usuario de IAM Identity Center/SSO o usuario IAM) y una tarjeta registrada.
- **DuckDNS** (gratis, se entra con Google/GitHub): <https://www.duckdns.org>. Crea tu subdominio, por ejemplo `mi-app` → `mi-app.duckdns.org`.
- **GitHub** con la llave SSH configurada, si la API está en un repositorio privado.

### Herramientas en tu computadora

| Herramienta | Versión | Instalación (macOS con Homebrew) |
|---|---|---|
| AWS CLI | v2 | `brew install awscli` |
| Terraform | ≥ 1.9 | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| Ansible | completo (incluye `community.general`) | `brew install ansible` |
| Node.js | ≥ 18 (solo para la prueba de WebSockets) | `brew install node` |
| git, openssl, dig, curl | — | Ya vienen en macOS |

> En Linux: usa el gestor de paquetes de tu distribución (`apt`, `dnf`) o las guías oficiales de cada herramienta. Funciona igual en Mac Intel o Apple Silicon (M1–M4).

Comprueba que todo está instalado:

```bash
aws --version && terraform version && ansible --version | head -1 && node --version
```

---

## ⚙️ Configuración: archivos `.example`

El repositorio **no incluye datos reales** (IPs, contraseñas, tokens). En su lugar trae **plantillas** que terminan en `.example`. **Debes copiarlas y reemplazar los valores** para que el proyecto funcione:

```bash
cp terraform.tfvars.example terraform.tfvars
cp ansible/vars.yml.example ansible/vars.yml
```

> ⚠️ **Copia, no renombres.** El `.example` debe seguir existiendo (es la plantilla del repositorio). Tus copias (`terraform.tfvars`, `vars.yml`) están en `.gitignore` y nunca se suben.
>
> `ansible/inventory.ini.example` **no** se copia: el `inventory.ini` real lo genera Terraform automáticamente.

### 1. `terraform.tfvars`

| Variable | Qué poner | Cómo obtenerlo |
|---|---|---|
| `aws_region` | `us-east-1` (u otra región) | Debe ser la misma donde está tu Key Pair |
| `aws_profile` | Nombre de tu perfil de AWS CLI | Ver [Credenciales de AWS](#credenciales-de-aws) |
| `domain_name` | `tu-subdominio.duckdns.org` | Tu subdominio en DuckDNS |
| `instance_count` | `3` | Número de servidores |
| `key_name` | Nombre del Key Pair, **sin** `.pem` | Ver [Key Pair](#key-pair-llave-ssh) |
| `ssh_private_key_path` | `~/.ssh/TU_LLAVE.pem` | Ruta donde guardaste el `.pem` |
| `ssh_allowed_cidrs` | `["TU_IP/32"]` | `curl -4 ifconfig.me` (usa la **IPv4**). Para pruebas puedes dejar `["0.0.0.0/0"]` |
| `health_check_path` | `/api/health` | Ruta de salud de tu API (debe responder 200) |
| `db_password` | Contraseña de la BD | Mínimo 8 caracteres, **sin** `@`, `/`, `"` ni espacios |

Las demás variables tienen valores por defecto razonables; todas están documentadas en `variables.tf`.

### 2. `ansible/vars.yml`

| Variable | Qué poner |
|---|---|
| `domain_name` | El mismo dominio que en `terraform.tfvars` |
| `duckdns_subdomain` | Solo la parte antes de `.duckdns.org` (ej. `mi-app`) |
| `duckdns_token` | Tu token de DuckDNS (en duckdns.org, arriba: **token**; si el navegador traduce la página aparece como **"simbólico"**) |
| `acme_email` | Tu correo (Let's Encrypt avisa si el certificado va a vencer) |
| `app_repo_url` | Repo de la API por SSH, ej. `git@github.com:TU_USUARIO/TU_API.git`. **Vacío** = solo prepara los servidores |
| `app_repo_version` | Rama a desplegar (ej. `main`, `develop`) |
| `app_compose_file` | Compose de producción dentro del repo de la API (ej. `docker-compose.prod.yml`) |
| `app_service` | Nombre del servicio en ese compose (ej. `api`) |
| `app_extra_env` | Variables extra para el `.env` de la API, ej. `JWT_SECRET` (genera uno con `openssl rand -hex 32`) |

### Credenciales de AWS

Terraform necesita saber con qué cuenta de AWS trabajar. Elige **una** opción:

**Opción A — IAM Identity Center / SSO (recomendada si entras a AWS por un portal `https://d-xxxx.awsapps.com/start`):**

```bash
aws configure sso
# SSO session name: mi-sesion
# SSO start URL:    https://d-xxxxxxxxxx.awsapps.com/start   (tu portal)
# SSO region:       us-east-1                                 (región de Identity Center)
# → se abre el navegador, aceptas, eliges cuenta y rol (AdministratorAccess)
# Default client Region: us-east-1
# Profile name: TU_PERFIL_AWS            ← ponlo en aws_profile de terraform.tfvars
```

La sesión SSO **expira cada día**; cuando veas `Token has expired`, renuévala con:

```bash
aws sso login --profile TU_PERFIL_AWS
```

**Opción B — Usuario IAM con access keys:** crea un usuario IAM dedicado (ej. `terraform`) con las políticas `AmazonEC2FullAccess`, `ElasticLoadBalancingFullAccess`, `AmazonRDSFullAccess`, `AmazonElastiCacheFullAccess` y `AWSCertificateManagerFullAccess`; crea una **clave de acceso** de tipo CLI y ejecuta `aws configure --profile TU_PERFIL_AWS`. **Nunca** uses claves del usuario root.

Comprueba:

```bash
aws sts get-caller-identity --profile TU_PERFIL_AWS
```

### Key Pair (llave SSH)

Los Key Pairs **existen solo en la región donde se crean**.

1. Consola de AWS → arriba a la derecha selecciona tu región (ej. **N. Virginia us-east-1**).
2. **EC2 → Red y seguridad → Pares de claves → Crear par de claves** → tipo **RSA**, formato **.pem**.
3. Guarda la llave con los permisos correctos:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
mv ~/Downloads/TU_LLAVE.pem ~/.ssh/TU_LLAVE.pem
chmod 400 ~/.ssh/TU_LLAVE.pem
```

### Llave de GitHub (solo si la API es privada)

Los servidores clonan tu repo **usando tu llave de GitHub a través de SSH** (agent forwarding); la llave nunca se copia a los servidores. Verifica:

```bash
ssh-add -l               # debe listar tu llave; si no: ssh-add --apple-use-keychain ~/.ssh/id_ed25519
ssh -T git@github.com    # debe decir: Hi TU_USUARIO! You've successfully authenticated
```

---

## 🚀 Despliegue paso a paso

> Todos los comandos de Terraform se ejecutan en la **raíz** del repositorio; los de Ansible, dentro de **`ansible/`**.

### Paso 1 — Certificado HTTPS (≈ 3 min)

```bash
cd ansible
ansible-playbook certificado.yml
cd ..
```

Obtiene un certificado de Let's Encrypt validando tu dominio con un registro TXT en DuckDNS. Los avisos `Unable to parse inventory.ini` son normales en este paso.
✅ Termina con `Certificado listo en certs/ (notAfter=...)`.

### Paso 2 — Crear la infraestructura (≈ 10 min)

```bash
terraform init
terraform plan     # revisa: debe decir "Plan: N to add, 0 to change, 0 to destroy"
terraform apply    # escribe: yes
```

✅ Termina con `Apply complete!` y muestra:

```text
public_ip      = "X.X.X.X"                    ← IP elástica (la del dominio)
app_url        = "https://tu-subdominio.duckdns.org"
ec2_instances  = { ...-ec2-1, ...-ec2-2, ...-ec2-3 }
rds_endpoint   = "....rds.amazonaws.com:5432"
redis_endpoint = "....cache.amazonaws.com:6379"
```

Terraform también escribe `ansible/inventory.ini` y `ansible/group_vars/all/infra.yml`: **no hay que copiar IPs a mano**.

### Paso 3 — Apuntar el dominio (≈ 1 min)

```bash
cd ansible
ansible-playbook duckdns.yml
```

✅ `tu-subdominio.duckdns.org -> X.X.X.X`

### Paso 4 — Configurar servidores y desplegar la API (≈ 15 min la primera vez)

```bash
ansible-playbook deploy.yml
```

Qué hace:

1. En las 3 EC2 a la vez: swap de 2 GB, Docker, firewall (UFW: solo 22 y 80), Fail2ban y Nginx con WebSockets.
2. Si `app_repo_url` está definido, **servidor por servidor**: clona la rama, genera el `.env`, construye la imagen y levanta el contenedor (`ASYNC POLL ... finished=False` mientras construye: es normal), verifica el health check y pasa al siguiente.
3. Comprueba `https://tu-subdominio.duckdns.org/api/health` de punta a punta.

✅ `PLAY RECAP` con `failed=0` y `unreachable=0` en las 3 instancias.

---

## 🧩 Requisitos de la aplicación (API)

La infraestructura sirve para cualquier API en Docker que escuche en el puerto `3000`, pero para aprovecharla al 100 % la API debe cumplir con esto:

### 1. Health check

Un endpoint que responda **200** (por defecto `GET /api/health`). Sin él, el ALB marca los servidores como caídos y responde `503`.

### 2. `docker-compose.prod.yml` en el repo de la API

```yaml
services:
  api:
    build: .
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"   # solo Nginx puede llegar (Docker se salta el firewall UFW)
    env_file: .env              # lo genera Ansible
```

### 3. Variables de entorno que Ansible genera en `.env`

`PORT`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_URL`, `INSTANCE_NAME` + todo lo de `app_extra_env`. Si tu API usa otros nombres, ajusta `ansible/app.env.j2`.

### 4. WebSockets entre servidores (Socket.IO + NestJS)

```bash
npm i @socket.io/redis-adapter redis
```

```ts
// src/adapters/redis-io.adapter.ts
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';
import { ServerOptions } from 'socket.io';

export class RedisIoAdapter extends IoAdapter {
  private adapterConstructor: ReturnType<typeof createAdapter>;

  async connectToRedis(url: string): Promise<void> {
    const pubClient = createClient({ url });
    const subClient = pubClient.duplicate();
    await Promise.all([pubClient.connect(), subClient.connect()]);
    this.adapterConstructor = createAdapter(pubClient, subClient);
  }

  createIOServer(port: number, options?: ServerOptions) {
    const server = super.createIOServer(port, options);
    server.adapter(this.adapterConstructor);
    return server;
  }
}
```

```ts
// src/main.ts (fragmento)
const app = await NestFactory.create<NestExpressApplication>(AppModule);
app.set('trust proxy', true);                 // IP real del cliente detrás de NLB → ALB → Nginx

if (process.env.REDIS_URL) {                   // en local, sin REDIS_URL, funciona como siempre
  const redisIoAdapter = new RedisIoAdapter(app);
  await redisIoAdapter.connectToRedis(process.env.REDIS_URL);
  app.useWebSocketAdapter(redisIoAdapter);
}

await app.listen(process.env.PORT ?? 3000, '0.0.0.0');
```

### 5. Frontend

- API: `https://tu-subdominio.duckdns.org/api`
- Socket.IO: `io('https://tu-subdominio.duckdns.org', { transports: ['websocket'] })`

---

## ✅ Verificar que todo funciona

**1. El balanceador reparte entre los 3 servidores:**

```bash
for i in 1 2 3 4 5 6; do curl -s https://tu-subdominio.duckdns.org/api/health; echo; done
```

Deben alternarse `...-ec2-1`, `...-ec2-2` y `...-ec2-3` en el campo `instance`.

**2. Los 3 servidores están conectados a Redis** (desde `ansible/`):

```bash
ansible webservers -b -m shell -a "docker logs SYSRANCHITO_API 2>&1 | grep -iE 'redis|escuchando' | tail -3"
```

> Sustituye `SYSRANCHITO_API` por el `container_name` de tu compose.

**3. Los WebSockets llegan entre servidores:**

```bash
cd scripts
npm install
node test-websockets.mjs https://tu-subdominio.duckdns.org
```

✅ `Recibieron el evento: 9/9` → los eventos llegan a los clientes de todos los servidores.

---

## 🔁 Operación del día a día

Desde `ansible/` (salvo que se indique):

| Quiero… | Comando |
|---|---|
| Desplegar una nueva versión de la API | `git push` en la rama configurada y luego `ansible-playbook deploy.yml --tags app` |
| Forzar reconstrucción aunque no haya cambios | `ansible-playbook deploy.yml --tags app -e force_deploy=true` |
| Actualizar un solo servidor | `ansible-playbook deploy.yml --limit sysranchito-dev-ec2-1` |
| Ver logs de los 3 servidores | `ansible webservers -b -m shell -a "docker logs --tail 50 NOMBRE_CONTENEDOR"` |
| Probar conexión a los servidores | `ansible webservers -m ping` |
| Entrar por SSH a un servidor | `ssh -i ~/.ssh/TU_LLAVE.pem ubuntu@IP_DEL_SERVIDOR` (IPs en `inventory.ini`) |
| Ver el estado de los servidores en el ALB | `aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names sysranchito-dev-tg --query 'TargetGroups[0].TargetGroupArn' --output text) --output table` |
| Renovar sesión de AWS (SSO) | `aws sso login --profile TU_PERFIL_AWS` |

### Renovar el certificado (cada ~60 días)

Let's Encrypt emite certificados de **90 días**. El output `certificate_expires` de Terraform muestra la fecha.

```bash
cd ansible && ansible-playbook certificado.yml && cd ..
terraform apply      # re-importa el certificado en ACM sin cortar el servicio
```

---

## ⏯️ Apagar y volver a encender

Mientras está encendido, la infraestructura cobra por hora. Para un entorno de pruebas, **apágala cuando no la uses**:

```bash
terraform destroy    # escribe: yes  (≈ 10 min)
```

- Se borra todo lo que cobra (EC2, NLB, ALB, IP elástica, Redis, RDS). **Los datos de la base de datos se pierden.**
- Se conservan en tu computadora: el código, tus `terraform.tfvars` / `vars.yml` y el certificado (`certs/`).

Para volver a encenderla (≈ 25 min, sin copiar nada a mano):

```bash
terraform apply
cd ansible
ansible-playbook duckdns.yml     # la IP elástica será otra; esto la actualiza en DuckDNS
ansible-playbook deploy.yml
```

---

## 🛠️ Solución de problemas

| Síntoma / error | Causa | Solución |
|---|---|---|
| `No valid credential sources found` | Terraform no encuentra credenciales de AWS | Revisa `aws_profile` en `terraform.tfvars` y ejecuta `aws sso login --profile TU_PERFIL_AWS` |
| `Token has expired and refresh failed` | La sesión SSO venció (dura horas) | `aws sso login --profile TU_PERFIL_AWS` |
| `Error: No configuration files` | Ejecutaste Terraform dentro de `ansible/` | `cd ..` a la raíz del repo |
| `InvalidKeyPair.NotFound` | El Key Pair no existe en esa región | Créalo en la región de `aws_region` |
| Error de RDS sobre la contraseña | Carácter no permitido | Usa solo letras, números y símbolos distintos de `@ / "` y espacio |
| `Configura duckdns_token...` en `certificado.yml` | `vars.yml` aún tiene el valor de ejemplo | Pon tu token real de DuckDNS |
| Ansible: `UNREACHABLE` / `timed out` | Tu IP pública cambió y el firewall no te deja entrar por SSH | `curl -4 ifconfig.me`, actualiza `ssh_allowed_cidrs` y `terraform apply` |
| `curl ifconfig.me` devuelve algo como `2806:...` | Es tu IPv6 | Usa `curl -4 ifconfig.me` |
| Ansible se queda mucho tiempo en un paso | El servidor (1 GB RAM) está ocupado construyendo | Espera; si pasan >15 min sin avance, `Ctrl+C` y vuelve a ejecutar (es seguro repetirlo) |
| El sitio responde `502` / `503` | La API no está corriendo o no responde el health check | `ansible webservers -b -m shell -a "docker ps -a; docker logs --tail 30 NOMBRE_CONTENEDOR"` |
| `terraform destroy` falla con `ResourceInUse` en un listener | AWS aún no suelta el ALB del NLB | Espera 2–5 min y vuelve a ejecutar `terraform destroy` |
| VS Code marca en rojo una variable de `terraform.tfvars` que sí existe | El editor guardó una versión vieja de `variables.tf` | Cierra pestañas sin guardar y, si VS Code avisa que el archivo cambió en disco, elige **Revert** |
| `compdef: command not found` al abrir la terminal | Detalle de tu `~/.zshrc`, no del proyecto | Puedes ignorarlo |

---

## 💰 Costos

Aproximados en `us-east-1`, con la configuración por defecto, **mientras está encendido**:

| Recurso | ~USD/mes |
|---|---|
| 3 × EC2 `t3.micro` | 23 |
| ALB | 17 |
| NLB | 17 |
| ElastiCache `cache.t4g.micro` | 12 |
| RDS `db.t4g.micro` (20 GB) | 15 |
| IPs públicas (1 elástica + 3 de las EC2) | 15 |
| **Total aproximado** | **≈ 95–100** |

Para pruebas: `terraform destroy` al terminar y `terraform apply` cuando lo necesites.

---

## 🔒 Seguridad

- **Nada sensible se sube a git:** tokens, contraseñas, IPs, certificados y el estado de Terraform están en `.gitignore`. Solo se suben las plantillas `.example`.
- **Solo el NLB es público.** El ALB es interno; las EC2 aceptan HTTP **solo desde el ALB** y SSH **solo desde `ssh_allowed_cidrs`**; RDS y Redis aceptan conexiones **solo desde las EC2**.
- La API se publica en `127.0.0.1` dentro de cada servidor: solo Nginx puede llegar a ella.
- TLS 1.2/1.3 en el ALB (`ELBSecurityPolicy-TLS13-1-2-2021-06`) y redirección automática de HTTP → HTTPS.
- Fail2ban bloquea intentos repetidos de SSH; UFW solo abre los puertos 22 y 80.
- `terraform.tfstate` contiene la llave privada del certificado y la contraseña de la BD: **no lo compartas**. Para equipos, muévelo a un backend S3 cifrado.

---

## 🧭 Limitaciones y mejoras futuras

- **NLB en una sola zona** (para tener una sola IP): si esa zona de AWS falla, el sitio cae. Es el costo de usar DuckDNS con una IP fija. Con un dominio propio en Route 53 se puede usar solo el ALB en varias zonas, con un certificado de ACM gratuito y renovación automática.
- **El certificado se renueva manualmente** cada ~60 días.
- **Cada servidor construye la imagen** (~5 min en `t3.micro`). Mejora: construirla una vez en GitHub Actions, subirla a ECR y que los servidores solo la descarguen.
- **Instancias fijas.** Mejora: Auto Scaling Group para reemplazar servidores caídos automáticamente.
- **`synchronize: true` en TypeORM** (si tu API lo usa): conviene pasar a migraciones antes de tener datos reales. El playbook ya soporta ejecutarlas una sola vez con `app_migration_command`.
