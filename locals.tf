data "yandex_client_config" "client" {}

locals {
  folder_id     = var.folder_id != "" ? var.folder_id : data.yandex_client_config.client.folder_id
  network_id    = yandex_vpc_network.metric.id
  subnet_a_id   = yandex_vpc_subnet.metric-a.id
  subnet_b_id   = yandex_vpc_subnet.metric-b.id
  subnet_d_id   = yandex_vpc_subnet.metric-d.id
  subnet_a_zone = yandex_vpc_subnet.metric-a.zone
  subnet_b_zone = yandex_vpc_subnet.metric-b.zone
  subnet_d_zone = yandex_vpc_subnet.metric-d.zone
  ingress_ip    = yandex_vpc_address.addr.external_ipv4_address[0].address
  metric_fqdn   = "metric.${local.ingress_ip}.sslip.io"
  s3_bucket     = "metric-blobs-${local.folder_id}"
  s3_endpoint   = "https://storage.yandexcloud.net"
  s3_region     = "ru-central1"
}
