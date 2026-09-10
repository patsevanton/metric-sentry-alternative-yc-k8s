resource "yandex_vpc_network" "metric" {
  name      = "metric-vpc"
  folder_id = local.folder_id
}

resource "yandex_vpc_gateway" "metric_nat" {
  folder_id   = local.folder_id
  name        = "metric-nat"
  description = "NAT gateway for private subnets egress"

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "metric_rt" {
  folder_id  = local.folder_id
  name       = "metric-rt"
  network_id = yandex_vpc_network.metric.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.metric_nat.id
  }
}

resource "yandex_vpc_subnet" "metric-a" {
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.1.0/24"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.metric.id
  route_table_id = yandex_vpc_route_table.metric_rt.id
}

resource "yandex_vpc_subnet" "metric-b" {
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.2.0/24"]
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.metric.id
  route_table_id = yandex_vpc_route_table.metric_rt.id
}

resource "yandex_vpc_subnet" "metric-d" {
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.3.0/24"]
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.metric.id
  route_table_id = yandex_vpc_route_table.metric_rt.id
}
