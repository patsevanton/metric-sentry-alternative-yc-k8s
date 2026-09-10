resource "yandex_vpc_address" "addr" {
  name      = "metric-pip"
  folder_id = local.folder_id

  external_ipv4_address {
    zone_id = local.subnet_a_zone
  }
}

# Публичный DNS не требуется: используются sslip.io-имена вида
# metric.<LB_IP>.sslip.io, которые резолвятся в IP балансировщика Traefik.

resource "local_file" "metric_values" {
  content = templatefile("${path.module}/metric-values.yaml.tpl", {
    fqdn        = local.metric_fqdn
    s3_endpoint = local.s3_endpoint
    s3_region   = local.s3_region
    s3_bucket   = local.s3_bucket
  })
  filename = "${path.module}/metric-values.yaml"
}
