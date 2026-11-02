# 🚀 INFRA-SYSBAR — Infraestructura con Auto Scaling en AWS

Este repositorio crea y configura, con unos pocos comandos, todo lo necesario para publicar una **API en Docker con WebSockets** (probada con NestJS) en internet. Usa un **grupo de servidores que crece y se reduce solo según el tráfico** (Auto Scaling), con **HTTPS** y un **dominio gratuito de DuckDNS**.

- **Terraform** crea la infraestructura en AWS: balanceadores, Auto Scaling Group, base de datos, Redis y permisos.
- **Cada servidor se configura solo al encenderse** (cloud-init): instala Docker y Nginx, clona tu API y la levanta.
- **Ansible** obtiene el certificado, apunta el dominio y despliega nuevas versiones en los servidores que estén vivos.

> 💡 **En palabras simples:** tu aplicación no vive en una sola computadora, sino en un **equipo de computadoras** que AWS administra por ti. En horas tranquilas basta con 1. Normalmente hay 3. Si llega mucha gente, AWS enciende más, hasta 10, y cuando la gente se va, las apaga para no cobrarte de más. Un "recepcionista" (el balanceador) reparte a cada visitante entre las computadoras disponibles.

---

## 📑 Índice

1. [Arquitectura](#-arquitectura)
2. [Auto Scaling: mínimo 1, recomendado 3, máximo 10](#-auto-scaling-mínimo-1-recomendado-3-máximo-10)
3. [Glosario rápido](#-glosario-rápido)
4. [Estructura del repositorio](#-estructura-del-repositorio)
5. [Requisitos](#-requisitos)
6. [Configuración: archivos `.example`](#%EF%B8%8F-configuración-archivos-example)
7. [Despliegue paso a paso](#-despliegue-paso-a-paso)
8. [Requisitos de la aplicación (API)](#-requisitos-de-la-aplicación-api)
9. [Verificar que todo funciona](#-verificar-que-todo-funciona)
10. [Operación del día a día](#-operación-del-día-a-día)
11. [Apagar y volver a encender](#%EF%B8%8F-apagar-y-volver-a-encender)
12. [Solución de problemas](#%EF%B8%8F-solución-de-problemas)
13. [Costos](#-costos)
14. [Seguridad](#-seguridad)
15. [Limitaciones y mejoras futuras](#-limitaciones-y-mejoras-futuras)

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
                     └──────────────┬───────────────┘
                                    ▼
        ┌────────────────── Auto Scaling Group (mín 1 · deseado 3 · máx 10) ──────────────────┐
        │   instancia (1a)     instancia (1b)     instancia (1c)     …  hasta 10               │
        │   Nginx :80 → API :3000 (Docker), configuradas solas con cloud-init                   │
        └───────┬───────────────────────────────┬──────────────────────────────┬───────────────┘
                ▼                               ▼                              ▼
       RDS PostgreSQL                 ElastiCache Redis              SSM Parameter Store
       (compartida)                   (Socket.IO entre servidores)   (.env y deploy key cifrados)
```

| Pieza | Qué hace (simple) | Detalle técnico |
|---|---|---|
| **DuckDNS** | El "nombre" de tu sitio | Registro A apuntando a la IP elástica del NLB |
| **NLB** (Network Load Balancer) | La puerta de entrada con una **dirección fija** | Única IP pública estable; reenvía TCP 80/443 al ALB |
| **ALB** (Application Load Balancer) | El recepcionista que reparte a los visitantes | Interno; termina TLS, health checks, *sticky sessions*, idle timeout de 3600 s |
| **Auto Scaling Group** | El jefe de turno que decide cuántas computadoras trabajan | Mín 1, deseado 3, máx 10; escala por CPU y por peticiones; reemplaza instancias caídas |
| **Launch Template** | El "molde" con el que nace cada computadora | Ubuntu 24.04, `t3.micro`, disco gp3 cifrado, rol IAM, script de arranque |
| **Instancias EC2** | Las computadoras donde corre tu API | Nginx → contenedor Docker; repartidas en las zonas a, b y c |
| **SSM Parameter Store** | La caja fuerte de la configuración | `.env` y deploy key como `SecureString`; cada instancia los lee al arrancar |
| **RDS PostgreSQL** | La base de datos que comparten todas | `db.t4g.micro`, privada, solo accesible desde las instancias |
| **ElastiCache Redis** | El "chat interno" entre servidores | Adaptador de Socket.IO: un evento emitido en un servidor llega a los clientes de los demás |
| **ACM** | Guarda el candado HTTPS | Certificado de Let's Encrypt importado (ACM no emite para `duckdns.org`) |

**¿Por qué NLB + ALB y no solo ALB?** Un ALB **no puede tener IP fija**, y DuckDNS **solo acepta IPs** (no permite apuntar a un nombre/CNAME). El NLB aporta la IP fija; el ALB aporta el reparto inteligente HTTP/WebSocket y el HTTPS.

**¿Por qué Redis?** Con WebSockets, cada usuario queda conectado a **un** servidor. Si la caja está en el servidor 1 y la cocina en el servidor 2, sin Redis la cocina nunca se enteraría de la orden. Redis comparte los eventos entre todos.

---

## 📈 Auto Scaling: mínimo 1, recomendado 3, máximo 10

| Valor | Variable | Por defecto | Significado |
|---|---|---|---|
| **Mínimo** | `asg_min_size` | **1** | Nunca habrá menos instancias, aunque no haya tráfico |
| **Recomendado (deseado)** | `asg_desired_capacity` | **3** | Con cuántas instancias arranca el grupo |
| **Máximo** | `asg_max_size` | **10** | Tope cuando el tráfico es máximo |

### ¿Cuándo crece y cuándo se reduce?

El grupo usa dos políticas de **target tracking**. AWS intenta mantener cada métrica cerca de su objetivo:

| Política | Variable | Objetivo | Efecto |
|---|---|---|---|
| CPU promedio | `scaling_cpu_target` | **60 %** | Si la CPU promedio pasa de 60 %, agrega instancias |
| Peticiones por instancia | `scaling_requests_per_target` | **1000 / min** | Si cada instancia recibe más de 1000 peticiones por minuto, agrega instancias |

- **Crece** si **cualquiera** de las dos métricas supera su objetivo.
- **Se reduce** solo cuando **ambas** están por debajo, y nunca baja de `asg_min_size`.
- AWS reduce de forma conservadora: tras un pico, las instancias extra se retiran poco a poco (minutos).

### Qué pasa cuando nace una instancia

1. El ASG la lanza con el **launch template** en la zona con menos instancias.
2. **cloud-init** ejecuta el bootstrap (`templates/user_data.sh.tftpl`): crea el swap, instala Docker, Nginx, UFW y Fail2ban, lee el `.env` y la deploy key de **SSM**, clona la rama de tu API y hace `docker compose up --build`.
3. Mientras construye (**≈ 8–10 min** en `t3.micro`), el ALB aún no le manda tráfico.
4. Cuando `GET /api/health` responde 200, el ALB la marca como sana y empieza a recibir usuarios.
5. Si una instancia deja de responder, el ASG la **reemplaza automáticamente** por una nueva.

> ⚠️ Una instancia nueva tarda ~10 minutos en estar lista, porque construye la imagen de Docker. El escalado sirve para aumentos de tráfico sostenidos, no para picos de segundos. Para escalar más rápido, mira [Limitaciones y mejoras](#-limitaciones-y-mejoras-futuras).

> 🔌 **WebSockets y reducción:** cuando el grupo se reduce, los usuarios conectados a la instancia que se retira pierden la conexión unos segundos. Socket.IO se **reconecta solo** a otra instancia.

### Cambiar el tamaño a mano

```bash
# Ver el estado del grupo
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names sysranchito-dev-asg \
  --query 'AutoScalingGroups[0].{min:MinSize,deseado:DesiredCapacity,max:MaxSize,instancias:Instances[].[InstanceId,AvailabilityZone,HealthStatus,LifecycleState]}'

# Fijar el número de instancias ahora mismo (entre el mínimo y el máximo)
aws autoscaling set-desired-capacity --auto-scaling-group-name sysranchito-dev-asg --desired-capacity 5
```

Para cambiar el **mínimo o el máximo**, edita `asg_min_size` / `asg_max_size` en `terraform.tfvars` y ejecuta `terraform apply`. Terraform ignora a propósito los cambios en el número deseado, porque ese valor lo ajustan las políticas de escalado.

---

## 📖 Glosario rápido

| Término | Significado |
|---|---|
| **AWS** | Amazon Web Services: la nube donde se rentan los servidores |
| **Región** | Ubicación física de AWS. Este proyecto usa `us-east-1` (Norte de Virginia) |
| **EC2 / instancia** | Un servidor virtual (una computadora en la nube) |
| **Auto Scaling Group (ASG)** | Grupo de instancias que AWS agranda, reduce y repara automáticamente |
| **Launch Template** | Molde con el que se crea cada instancia del ASG |
| **Target tracking** | Política de escalado que mantiene una métrica (CPU, peticiones) cerca de un objetivo |
| **cloud-init / user_data** | Script que una instancia ejecuta sola la primera vez que enciende |
| **Instance refresh** | Reemplazo gradual de todas las instancias por otras nuevas, sin cortar el servicio |
| **SSM Parameter Store** | Almacén de AWS para configuración y secretos cifrados |
| **Deploy key** | Llave SSH de **solo lectura** para un único repositorio de GitHub |
| **Key Pair / `.pem`** | La "llave" para entrar por SSH a las instancias. Es por región |
| **Security Group** | Firewall de AWS: decide quién puede conectarse a qué puerto |
| **IP elástica** | IP pública fija que no cambia |
| **Terraform** | Herramienta que crea infraestructura a partir de archivos `.tf` |
| **`terraform.tfstate`** | "Memoria" de Terraform: qué creó. Contiene datos sensibles |
| **Ansible** | Herramienta que se conecta por SSH y ejecuta tareas con *playbooks* (`.yml`) |
| **Inventario dinámico** | Lista de servidores que Ansible obtiene de AWS en cada ejecución |
| **Health check** | Revisión periódica: si un servidor no responde 200, deja de recibir tráfico |
| **Rolling deploy** | Actualizar los servidores uno por uno, sin apagar el servicio |

---

## 📁 Estructura del repositorio

```text
infra-sysbar/
├── provider.tf               # Proveedores (aws, local, time) y perfil de AWS
├── variables.tf              # Todas las variables configurables (con descripción)
├── locals.tf                 # Valores calculados (nombres, zonas, contenido del .env)
├── network.tf                # VPC por defecto, subnets y AMI de Ubuntu 24.04
├── security_groups.tf        # Firewalls de NLB, ALB e instancias
├── asg.tf                    # Launch template, Auto Scaling Group y políticas de escalado
├── iam.tf                    # Rol de las instancias (leer SSM + Session Manager)
├── ssm.tf                    # .env y deploy key cifrados en SSM Parameter Store
├── alb.tf                    # ALB interno, target group y listeners 80/443
├── nlb.tf                    # IP elástica, NLB y conexión NLB → ALB
├── certificate.tf            # Importa el certificado de certs/ a ACM
├── rds.tf                    # PostgreSQL
├── redis.tf                  # ElastiCache Redis
├── ansible_inventory.tf      # Genera la configuración que usa Ansible
├── outputs.tf                # Datos que muestra Terraform al terminar
├── templates/
│   └── user_data.sh.tftpl    # Bootstrap de cada instancia (Docker, Nginx, firewall, app-deploy)
├── terraform.tfvars.example  # 📝 PLANTILLA → copiar a terraform.tfvars
├── ansible/
│   ├── ansible.cfg           # Configuración de Ansible (inventario dinámico, SSH estable)
│   ├── inventory.py          # Inventario dinámico: instancias vivas del ASG (usa la AWS CLI)
│   ├── certificado.yml       # Certificado HTTPS (corre en tu computadora)
│   ├── duckdns.yml           # Apunta el dominio a la IP elástica
│   ├── deploy.yml            # Despliega una nueva versión en las instancias vivas (rolling)
│   └── vars.yml.example      # 📝 PLANTILLA → copiar a vars.yml
└── scripts/
    ├── package.json
    └── test-websockets.mjs   # Prueba de WebSockets entre servidores
```

**Archivos locales que NUNCA se suben a git** (ya están en `.gitignore`):

| Archivo | Lo crea | Contiene |
|---|---|---|
| `terraform.tfvars` | Tú (desde el `.example`) | Tu configuración, contraseña de la BD y secretos de la app |
| `ansible/vars.yml` | Tú (desde el `.example`) | Token de DuckDNS y correo |
| `secrets/github_deploy_key` | Tú (`ssh-keygen`) | Llave privada de solo lectura para clonar la API |
| `certs/` | `certificado.yml` | Certificado y **llave privada** HTTPS |
| `ansible/.aws_inventory.json` | Terraform | Región, perfil y nombre del ASG para el inventario dinámico |
| `ansible/group_vars/all/infra.yml` | Terraform | IP elástica, nombre del ASG, puerto y health check |
| `terraform.tfstate*` | Terraform | Estado completo (incluye secretos) |

---

## 📋 Requisitos

### Cuentas

- **AWS** con permisos de administrador (usuario de IAM Identity Center/SSO o usuario IAM) y una tarjeta registrada. Terraform crea un rol IAM, así que se necesitan permisos de IAM.
- **DuckDNS** (gratis, se entra con Google/GitHub): <https://www.duckdns.org>. Crea tu subdominio, por ejemplo `mi-app` → `mi-app.duckdns.org`.
- **GitHub**: el repositorio de tu API. Si es privado, necesitas permiso para agregarle una **deploy key**.

### Herramientas en tu computadora

| Herramienta | Versión | Instalación (macOS con Homebrew) |
|---|---|---|
| AWS CLI | v2 | `brew install awscli` |
| Terraform | ≥ 1.9 | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| Ansible | completo (incluye `community.general`) | `brew install ansible` |
| Python 3 | ≥ 3.8 (lo usa el inventario dinámico) | Ya viene en macOS (Xcode CLT) |
| Node.js | ≥ 18 (solo para la prueba de WebSockets) | `brew install node` |
| git, ssh-keygen, openssl, dig, curl | — | Ya vienen en macOS |

> En Linux: usa el gestor de paquetes de tu distribución (`apt`, `dnf`) o las guías oficiales de cada herramienta. Funciona igual en Mac Intel o Apple Silicon (M1–M4).

```bash
aws --version && terraform version && ansible --version | head -1 && python3 --version && node --version
```

---

## ⚙️ Configuración: archivos `.example`

El repositorio **no incluye datos reales** (IPs, contraseñas, tokens, llaves). En su lugar trae **plantillas** que terminan en `.example`. **Debes copiarlas y reemplazar los valores** para que el proyecto funcione:

```bash
cp terraform.tfvars.example terraform.tfvars
cp ansible/vars.yml.example ansible/vars.yml
```

> ⚠️ **Copia, no renombres.** El `.example` debe seguir existiendo (es la plantilla del repositorio). Tus copias están en `.gitignore` y nunca se suben.

### 1. `terraform.tfvars` — infraestructura y aplicación

| Variable | Qué poner | Cómo obtenerlo |
|---|---|---|
| `aws_region` | `us-east-1` (u otra región) | Debe ser la misma donde está tu Key Pair |
| `aws_profile` | Nombre de tu perfil de AWS CLI | Ver [Credenciales de AWS](#credenciales-de-aws) |
| `domain_name` | `tu-subdominio.duckdns.org` | Tu subdominio en DuckDNS |
| `key_name` | Nombre del Key Pair, **sin** `.pem` | Ver [Key Pair](#key-pair-llave-ssh) |
| `ssh_private_key_path` | `~/.ssh/TU_LLAVE.pem` | Ruta donde guardaste el `.pem` |
| `ssh_allowed_cidrs` | `["TU_IP/32"]` | `curl -4 ifconfig.me` (usa la **IPv4**). Para pruebas puedes dejar `["0.0.0.0/0"]` |
| `asg_min_size` / `asg_desired_capacity` / `asg_max_size` | `1` / `3` / `10` | Ver [Auto Scaling](#-auto-scaling-mínimo-1-recomendado-3-máximo-10) |
| `app_repo_url` | `git@github.com:TU_USUARIO/TU_API.git` | Repo de la API (SSH si es privado, `https://` si es público) |
| `app_repo_version` | Rama a desplegar (ej. `main`, `develop`) | — |
| `app_compose_file` | `docker-compose.prod.yml` | Compose de producción dentro del repo de la API |
| `app_port` | `3000` | Puerto donde escucha tu API |
| `github_deploy_key_path` | `secrets/github_deploy_key` | Ver [Deploy key](#deploy-key-de-github-repo-privado). Vacío (`""`) si el repo es público |
| `app_extra_env` | Mapa de variables extra del `.env` | Ej. `JWT_SECRET` (genera uno con `openssl rand -hex 32`), `NODE_ENV` |
| `health_check_path` | `/api/health` | Ruta de salud de tu API (debe responder 200) |
| `db_password` | Contraseña de la BD | Mínimo 8 caracteres, **sin** `@`, `/`, `"` ni espacios |

Las demás variables tienen valores por defecto razonables; todas están documentadas en `variables.tf`.

### 2. `ansible/vars.yml` — dominio y certificado

| Variable | Qué poner |
|---|---|
| `domain_name` | El mismo dominio que en `terraform.tfvars` |
| `duckdns_subdomain` | Solo la parte antes de `.duckdns.org` (ej. `mi-app`) |
| `duckdns_token` | Tu token de DuckDNS (en duckdns.org, arriba: **token**; si el navegador traduce la página aparece como **"simbólico"**) |
| `acme_email` | Tu correo (Let's Encrypt avisa si el certificado va a vencer) |

### Credenciales de AWS

Terraform y el inventario dinámico de Ansible necesitan saber con qué cuenta de AWS trabajar. Elige **una** opción:

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

**Opción B — Usuario IAM con access keys:** crea un usuario IAM dedicado (ej. `terraform`) con `AdministratorAccess` (Terraform crea roles IAM, Auto Scaling, EC2, ELB, RDS, ElastiCache, SSM y ACM). Crea una **clave de acceso** de tipo CLI y ejecuta `aws configure --profile TU_PERFIL_AWS`. **Nunca** uses claves del usuario root.

```bash
aws sts get-caller-identity --profile TU_PERFIL_AWS
```

### Key Pair (llave SSH)

Los Key Pairs **existen solo en la región donde se crean**.

1. En la consola de AWS, arriba a la derecha, selecciona tu región (ej. **N. Virginia us-east-1**).
2. **EC2 → Red y seguridad → Pares de claves → Crear par de claves** → tipo **RSA**, formato **.pem**.
3. Guarda la llave con los permisos correctos:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
mv ~/Downloads/TU_LLAVE.pem ~/.ssh/TU_LLAVE.pem
chmod 400 ~/.ssh/TU_LLAVE.pem
```

### Deploy key de GitHub (repo privado)

Las instancias del Auto Scaling Group nacen solas, sin ti conectado, así que necesitan su **propia** llave para clonar la API. Se usa una **deploy key**: una llave SSH de **solo lectura** que solo sirve para **un** repositorio.

1. Genera la llave (desde la raíz de este repo):

   ```bash
   mkdir -p secrets
   ssh-keygen -t ed25519 -N "" -C "deploy-key-infra-sysbar" -f secrets/github_deploy_key
   cat secrets/github_deploy_key.pub      # copia esta línea
   ```

2. En GitHub, abre **el repositorio de la API → Settings → Deploy keys → Add deploy key**.
   - **Title:** `infra-sysbar (AWS Auto Scaling)`
   - **Key:** pega el contenido de `github_deploy_key.pub`
   - **No** marques *Allow write access* (solo lectura).
   - Clic en **Add key**.

3. En `terraform.tfvars`: `github_deploy_key_path = "secrets/github_deploy_key"`.

Terraform guarda la llave privada **cifrada en SSM**. Cada instancia la descarga al arrancar. Si el repo es **público**, usa una URL `https://` en `app_repo_url` y deja `github_deploy_key_path = ""`.

---

## 🚀 Despliegue paso a paso

> Todos los comandos de Terraform se ejecutan en la **raíz** del repositorio; los de Ansible, dentro de **`ansible/`**.

### Paso 1 — Certificado HTTPS (≈ 3 min)

```bash
cd ansible
ansible-playbook certificado.yml
cd ..
```

Obtiene un certificado de Let's Encrypt validando tu dominio con un registro TXT en DuckDNS. Si aparece algún aviso sobre el inventario en este paso, es normal: todavía no hay instancias.
✅ Termina con `Certificado listo en certs/ (notAfter=...)`.

### Paso 2 — Deploy key (solo la primera vez)

Si tu API está en un repo privado, sigue [Deploy key de GitHub](#deploy-key-de-github-repo-privado).

### Paso 3 — Crear la infraestructura (≈ 10 min + ≈ 10 min de arranque)

```bash
terraform init
terraform plan     # revisa: "Plan: N to add, 0 to change, 0 to destroy"
terraform apply    # escribe: yes
```

✅ Termina con `Apply complete!` y muestra:

```text
public_ip      = "X.X.X.X"                    ← IP elástica (la del dominio)
app_url        = "https://tu-subdominio.duckdns.org"
autoscaling    = { name = "...-asg", min = 1, desired = 3, max = 10 }
rds_endpoint   = "....rds.amazonaws.com:5432"
redis_endpoint = "....cache.amazonaws.com:6379"
```

> ⏳ `terraform apply` termina **antes** de que las instancias estén listas. Durante los siguientes **~10 minutos**, el ASG enciende 3 instancias y cada una se configura y construye la API sola. No hace falta ejecutar ningún playbook para eso.

### Paso 4 — Apuntar el dominio (≈ 1 min)

```bash
cd ansible
ansible-playbook duckdns.yml
```

✅ `tu-subdominio.duckdns.org -> X.X.X.X`

### Paso 5 — Comprobar que las instancias quedaron listas

```bash
./inventory.py --list                 # instancias vivas del ASG con su IP
ansible webservers -m ping            # Ansible llega a todas
ansible-playbook deploy.yml           # opcional: espera el bootstrap, verifica y confirma el sitio público
```

✅ `deploy.yml` termina con `https://tu-subdominio.duckdns.org respondió 200 a través de NLB -> ALB -> ASG`.

---

## 🧩 Requisitos de la aplicación (API)

La infraestructura sirve para cualquier API en Docker. Para aprovecharla al 100 %, la API debe cumplir con esto:

### 1. Health check

Un endpoint que responda **200** (por defecto `GET /api/health`). Sin él, el ALB marca las instancias como caídas y el ASG las reemplaza una y otra vez.

### 2. `docker-compose.prod.yml` en el repo de la API

```yaml
services:
  api:
    build: .
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"   # solo Nginx puede llegar (Docker se salta el firewall UFW)
    env_file: .env              # lo genera cada instancia desde SSM
```

### 3. Variables de entorno del `.env`

Cada instancia escribe el `.env` con `PORT`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_URL` y `INSTANCE_NAME` (el ID de la instancia), más todo lo de `app_extra_env`. Si tu API usa otros nombres, ajusta `local.app_env` en `locals.tf`.

### 4. Sin estado local (stateless)

Las instancias se crean y destruyen solas: **nada importante debe guardarse en su disco o en su memoria**. Sesiones en JWT o Redis, datos en RDS y archivos subidos en un servicio externo (ej. S3).

### 5. WebSockets entre servidores (Socket.IO + NestJS)

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

### 6. Frontend

- API: `https://tu-subdominio.duckdns.org/api`
- Socket.IO: `io('https://tu-subdominio.duckdns.org', { transports: ['websocket'] })`

---

## ✅ Verificar que todo funciona

**1. El balanceador reparte entre las instancias:**

```bash
for i in 1 2 3 4 5 6; do curl -s https://tu-subdominio.duckdns.org/api/health; echo; done
```

En el campo `instance` deben alternarse los IDs de las instancias (`i-0abc...`). En el navegador verás siempre la misma por la cookie de afinidad (*sticky session*); es normal.

**2. Todas las instancias están conectadas a Redis** (desde `ansible/`):

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

✅ `Recibieron el evento: 9/9`: los eventos llegan a los clientes de todos los servidores.

**4. El Auto Scaling repara solo:** termina una instancia desde la consola (**EC2 → Instancias → Terminar**). En unos minutos el ASG lanza otra para volver al número deseado, y el sitio sigue respondiendo con las demás.

---

## 🔁 Operación del día a día

Desde `ansible/` (salvo que se indique):

| Quiero… | Comando |
|---|---|
| Desplegar una nueva versión de la API | `git push` en la rama configurada y luego `ansible-playbook deploy.yml` |
| Cambiar variables del `.env` | Edita `app_extra_env` en `terraform.tfvars`, ejecuta `terraform apply` (en la raíz) y luego `ansible-playbook deploy.yml` |
| Ver las instancias vivas | `./inventory.py --list` |
| Actualizar una sola instancia | `ansible-playbook deploy.yml --limit i-0123456789abcdef0` |
| Ver logs de todas las instancias | `ansible webservers -b -m shell -a "docker logs --tail 50 NOMBRE_CONTENEDOR"` |
| Ver el log del bootstrap | `ansible webservers -b -m shell -a "tail -30 /var/log/sysbar-bootstrap.log"` |
| Entrar a una instancia | `ssh -i ~/.ssh/TU_LLAVE.pem ubuntu@IP` (IPs en `./inventory.py --list`) o **Session Manager** desde la consola de EC2 (botón *Conectar*) |
| Fijar el número de instancias | `aws autoscaling set-desired-capacity --auto-scaling-group-name sysranchito-dev-asg --desired-capacity 5` |
| Reemplazar todas las instancias por nuevas | `aws autoscaling start-instance-refresh --auto-scaling-group-name sysranchito-dev-asg` |
| Renovar sesión de AWS (SSO) | `aws sso login --profile TU_PERFIL_AWS` |

> **¿`deploy.yml` o instance refresh?** `deploy.yml` actualiza en el lugar las instancias que ya existen, en ~5 min por instancia. Las instancias **nuevas** que cree el ASG después siempre clonan la punta de la rama, así que quedan con la misma versión. Si cambias el bootstrap, la AMI o el tipo de instancia, `terraform apply` lanza un **instance refresh** automático: crea instancias nuevas primero y luego retira las viejas.

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

- Se borra todo lo que cobra: instancias del ASG, NLB, ALB, IP elástica, Redis, RDS y parámetros de SSM. **Los datos de la base de datos se pierden.**
- Se conservan en tu computadora: el código, tus `terraform.tfvars` / `vars.yml`, la deploy key y el certificado (`certs/`).

Para volver a encenderla (≈ 20 min, sin copiar nada a mano):

```bash
terraform apply
cd ansible
ansible-playbook duckdns.yml     # la IP elástica será otra; esto la actualiza en DuckDNS
```

Las instancias se configuran solas. Si quieres esperar a que estén listas y comprobar el sitio, ejecuta `ansible-playbook deploy.yml`.

---

## 🛠️ Solución de problemas

| Síntoma / error | Causa | Solución |
|---|---|---|
| `No valid credential sources found` | Terraform no encuentra credenciales de AWS | Revisa `aws_profile` en `terraform.tfvars` y ejecuta `aws sso login --profile TU_PERFIL_AWS` |
| `Token has expired and refresh failed` | La sesión SSO venció (dura horas) | `aws sso login --profile TU_PERFIL_AWS` |
| `Error: No configuration files` | Ejecutaste Terraform dentro de `ansible/` | `cd ..` a la raíz del repo |
| `InvalidKeyPair.NotFound` | El Key Pair no existe en esa región | Créalo en la región de `aws_region` |
| `Invalid function argument ... no file exists` en `ssm.tf` | No existe la deploy key en `github_deploy_key_path` | Genera la llave (ver [Deploy key](#deploy-key-de-github-repo-privado)) o pon `""` si el repo es público |
| Error de RDS sobre la contraseña | Carácter no permitido | Usa solo letras, números y símbolos distintos de `@ / "` y espacio |
| `Configura duckdns_token...` en `certificado.yml` | `vars.yml` aún tiene el valor de ejemplo | Pon tu token real de DuckDNS |
| `No hay instancias en el grupo webservers` | Inventario dinámico vacío | Sesión de AWS activa (`aws sso login`), `terraform apply` completo y `./inventory.py --list` |
| Ansible: `UNREACHABLE` / `timed out` | Tu IP pública cambió y el firewall no te deja entrar por SSH | `curl -4 ifconfig.me`, actualiza `ssh_allowed_cidrs` y `terraform apply` |
| Las instancias se reemplazan una y otra vez | El bootstrap falla o `/api/health` no responde 200 | `ansible webservers -b -m shell -a "tail -50 /var/log/sysbar-bootstrap.log"` |
| Log del bootstrap: `Permission denied (publickey)` en `git clone` | La deploy key no está agregada en GitHub o es de otro repo | Agrega `secrets/github_deploy_key.pub` en **Settings → Deploy keys** del repo de la API |
| El sitio responde `502` / `503` justo después del `apply` | Las instancias aún construyen la API (~10 min) | Espera; `ansible-playbook deploy.yml` espera por ti y verifica |
| `curl ifconfig.me` devuelve algo como `2806:...` | Es tu IPv6 | Usa `curl -4 ifconfig.me` |
| `terraform destroy` falla con `ResourceInUse` en un listener | AWS aún no suelta el ALB del NLB | Espera 2–5 min y vuelve a ejecutar `terraform destroy` |
| VS Code marca en rojo una variable de `terraform.tfvars` que sí existe | El editor guardó una versión vieja de `variables.tf` | Cierra pestañas sin guardar y, si VS Code avisa que el archivo cambió en disco, elige **Revert** |
| `compdef: command not found` al abrir la terminal | Detalle de tu `~/.zshrc`, no del proyecto | Puedes ignorarlo |

---

## 💰 Costos

Aproximados en `us-east-1`, precios de lista bajo demanda, **mientras está encendido**. Con Auto Scaling, el costo depende de cuántas instancias haya:

| Recurso | Precio | 1 instancia (mín) | 3 instancias (normal) | 10 instancias (máx) |
|---|---|---|---|---|
| EC2 `t3.micro` | $0.0104/h c/u | $7.59 | $22.78 | $75.92 |
| IP pública por instancia | $0.005/h c/u | $3.65 | $10.95 | $36.50 |
| Disco gp3 16 GB por instancia | $0.08/GB-mes | $1.28 | $3.84 | $12.80 |
| ALB | $0.0225/h + LCU | $16.43 | $16.43 | $16.43 + LCU |
| NLB + su IP elástica | $0.0225/h + $0.005/h | $20.08 | $20.08 | $20.08 + NLCU |
| ElastiCache `cache.t4g.micro` | $0.016/h | $11.68 | $11.68 | $11.68 |
| RDS `db.t4g.micro` + 20 GB | $0.016/h + $0.115/GB-mes | $13.98 | $13.98 | $13.98 |
| **Total aproximado / mes** | | **≈ $75** | **≈ $100** | **≈ $187** |

- El ASG solo llega a 10 instancias con tráfico alto sostenido. Con poco tráfico baja hasta 1 y el costo baja a ≈ $75 al mes.
- No incluye LCU/NLCU ni transferencia de salida; con tráfico bajo suman pocos dólares.
- Para pruebas: `terraform destroy` al terminar y `terraform apply` cuando lo necesites.

---

## 🔒 Seguridad

- **Nada sensible se sube a git:** tokens, contraseñas, deploy key, certificados y el estado de Terraform están en `.gitignore`. Solo se suben las plantillas `.example`.
- **Secretos cifrados en SSM:** el `.env` y la deploy key se guardan como `SecureString`. No viajan en el `user_data` ni quedan en la plantilla de lanzamiento.
- **Permisos mínimos:** el rol de las instancias solo puede **leer** los parámetros `/<proyecto>-<entorno>/app/*` y usar Session Manager.
- **Deploy key de solo lectura** y limitada a un solo repositorio.
- **Solo el NLB es público.** El ALB es interno; las instancias aceptan HTTP **solo desde el ALB** y SSH **solo desde `ssh_allowed_cidrs`**; RDS y Redis aceptan conexiones **solo desde las instancias**.
- La API se publica en `127.0.0.1` dentro de cada instancia: solo Nginx puede llegar a ella.
- Discos cifrados, IMDSv2 obligatorio, TLS 1.2/1.3 en el ALB y redirección automática de HTTP a HTTPS.
- Fail2ban bloquea intentos repetidos de SSH; UFW solo abre los puertos 22 y 80.
- `terraform.tfstate` contiene secretos (llave del certificado, contraseña de la BD, `.env`): **no lo compartas**. Para equipos, muévelo a un backend S3 cifrado.

---

## 🧭 Limitaciones y mejoras futuras

- **Arranque lento (~10 min por instancia):** cada instancia construye la imagen de Docker. Mejora: construir la imagen una vez en GitHub Actions, subirla a **ECR** y que las instancias solo la descarguen (arranque en ~2 min).
- **NLB en una sola zona** (para tener una sola IP): si esa zona de AWS falla, el sitio cae. Es el costo de usar DuckDNS con una IP fija. Con un dominio propio en Route 53 se puede usar solo el ALB en varias zonas, con certificado ACM gratuito y renovación automática.
- **El certificado se renueva manualmente** cada ~60 días.
- **IP pública por instancia** (para salida a internet y SSH). Mejora: subnets privadas con NAT o endpoints de VPC y acceso solo por Session Manager.
- **`synchronize: true` en TypeORM** (si tu API lo usa): con varias instancias arrancando a la vez, conviene pasar a migraciones antes de tener datos reales.
