# Certificado de Let's Encrypt (obtenido con ansible/certificado.yml vía DNS-01 en DuckDNS)
# importado a ACM para que el ALB termine TLS.
#
# ACM no puede emitir certificados para duckdns.org (no permite registros CNAME),
# por eso se importa. Para renovarlo: volver a correr certificado.yml y `terraform apply`.
resource "aws_acm_certificate" "app" {
  private_key       = file("${local.cert_dir}/privkey.pem")
  certificate_body  = file("${local.cert_dir}/cert.pem")
  certificate_chain = file("${local.cert_dir}/chain.pem")

  tags = { Name = "${local.name_prefix}-cert" }

  lifecycle {
    create_before_destroy = true
  }
}
