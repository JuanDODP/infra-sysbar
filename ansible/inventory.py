#!/usr/bin/env python3
"""
Inventario dinámico de Ansible para las instancias del Auto Scaling Group.

Las instancias no son fijas (el ASG las crea y las destruye según el tráfico), así que
en cada ejecución este script pregunta a AWS cuáles están corriendo y las expone en el
grupo `webservers`. Usa la AWS CLI con el mismo perfil que Terraform, sin dependencias
extra de Python (no necesita boto3).

Configuración: ansible/.aws_inventory.json (lo genera `terraform apply`).
Prueba manual:  ./inventory.py --list
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, ".aws_inventory.json")


def empty():
    return {"_meta": {"hostvars": {}}, "webservers": {"hosts": []}}


def fail(msg):
    print(f"[inventory.py] {msg}", file=sys.stderr)
    print(json.dumps(empty()))
    sys.exit(0)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--host":
        print("{}")
        return

    if not os.path.exists(CONFIG):
        fail("No existe .aws_inventory.json: ejecuta primero `terraform apply` en la raíz del repo.")

    with open(CONFIG) as f:
        cfg = json.load(f)

    cmd = [
        "aws", "ec2", "describe-instances",
        "--region", cfg["region"],
        "--filters",
        f"Name=tag:aws:autoscaling:groupName,Values={cfg['asg_name']}",
        "Name=instance-state-name,Values=running",
        "--query",
        "Reservations[].Instances[].{id:InstanceId,public:PublicIpAddress,private:PrivateIpAddress,az:Placement.AvailabilityZone,launched:LaunchTime}",
        "--output", "json",
    ]
    if cfg.get("profile"):
        cmd[1:1] = ["--profile", cfg["profile"]]

    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    except FileNotFoundError:
        fail("No se encontró la AWS CLI (`aws`). Instálala: brew install awscli")
    except subprocess.CalledProcessError as e:
        fail("La AWS CLI falló (¿sesión SSO expirada? -> aws sso login --profile PERFIL):\n" + e.stderr.strip())

    instances = sorted(json.loads(out or "[]"), key=lambda i: (i.get("az") or "", i.get("launched") or ""))

    inv = {
        "_meta": {"hostvars": {}},
        "webservers": {
            "hosts": [],
            "vars": {
                "ansible_user": cfg.get("ssh_user", "ubuntu"),
                "ansible_ssh_private_key_file": cfg["ssh_private_key_path"],
                # Las IPs se reutilizan entre instancias efímeras: no fijar host keys
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
            },
        },
    }
    for i in instances:
        if not i.get("public"):
            continue
        name = i["id"]
        inv["webservers"]["hosts"].append(name)
        inv["_meta"]["hostvars"][name] = {
            "ansible_host": i["public"],
            "private_ip": i.get("private"),
            "availability_zone": i.get("az"),
        }

    print(json.dumps(inv, indent=2))


if __name__ == "__main__":
    main()
