# Instancias EC2 de la aplicación, repartidas entre zonas de disponibilidad
resource "aws_instance" "app_server" {
  count = var.instance_count

  ami           = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  # ec2-1 -> us-east-1a, ec2-2 -> us-east-1b, ec2-3 -> us-east-1c
  subnet_id                   = local.subnet_ids[count.index % length(local.subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true # Necesaria para salir a Internet y para Ansible por SSH

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${local.name_prefix}-ec2-${count.index + 1}"
  }

  # Canonical publica AMIs nuevas seguido: no reemplazar servidores por eso
  lifecycle {
    ignore_changes = [ami]
  }
}
