output "public_ip" {
  description = "IP elástica del NLB: es la IP que debe tener tu dominio en DuckDNS"
  value       = aws_eip.nlb.public_ip
}

output "app_url" {
  description = "URL pública de la aplicación"
  value       = "https://${var.domain_name}"
}

output "nlb_dns_name" {
  description = "DNS del NLB público"
  value       = aws_lb.nlb.dns_name
}

output "alb_dns_name" {
  description = "DNS del ALB interno (solo accesible dentro de la VPC)"
  value       = aws_lb.alb.dns_name
}

output "autoscaling" {
  description = "Auto Scaling Group de la API (las instancias se crean y destruyen solas)"
  value = {
    name    = aws_autoscaling_group.app.name
    min     = aws_autoscaling_group.app.min_size
    desired = var.asg_desired_capacity
    max     = aws_autoscaling_group.app.max_size
  }
}

output "ver_instancias" {
  description = "Comando para ver las instancias vivas del Auto Scaling Group"
  value       = "cd ansible && ./inventory.py --list"
}

output "rds_endpoint" {
  description = "Endpoint de conexión para la base de datos PostgreSQL"
  value       = aws_db_instance.postgres_rds.endpoint
}

output "redis_endpoint" {
  description = "Endpoint de Redis para el adaptador de Socket.IO"
  value       = var.enable_redis ? "${aws_elasticache_cluster.redis[0].cache_nodes[0].address}:6379" : "deshabilitado"
}

output "certificate_expires" {
  description = "Fecha de expiración del certificado importado (renovar antes)"
  value       = aws_acm_certificate.app.not_after
}
