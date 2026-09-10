resource "yandex_iam_service_account" "sa_k8s_editor" {
  name      = "sa-k8s-editor"
  folder_id = local.folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "sa_k8s_editor_permissions" {
  folder_id = local.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa_k8s_editor.id}"
}

resource "time_sleep" "wait_sa" {
  create_duration = "20s"
  depends_on = [
    yandex_iam_service_account.sa_k8s_editor,
    yandex_resourcemanager_folder_iam_member.sa_k8s_editor_permissions
  ]
}

resource "yandex_kubernetes_cluster" "metric" {
  name       = "metric"
  folder_id  = local.folder_id
  network_id = local.network_id

  master {
    version = "1.33"
    regional {
      region = "ru-central1"

      location {
        zone      = local.subnet_a_zone
        subnet_id = local.subnet_a_id
      }

      location {
        zone      = local.subnet_b_zone
        subnet_id = local.subnet_b_id
      }

      location {
        zone      = local.subnet_d_zone
        subnet_id = local.subnet_d_id
      }
    }
    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.sa_k8s_editor.id
  node_service_account_id = yandex_iam_service_account.sa_k8s_editor.id
  release_channel         = "STABLE"
  depends_on              = [time_sleep.wait_sa]
}

# Medium-профиль Metric требует суммарно ~8 GiB RAM (Metric + MongoDB + Symbolicator),
# плюс накладные расходы kube-system и ingress. Одна нода 4 vCPU / 16 GiB покрывает это.
resource "yandex_kubernetes_node_group" "k8s_node_group_a" {
  description = "Node group for Managed Kubernetes cluster in zone A"
  name        = "k8s-node-group-a"
  cluster_id  = yandex_kubernetes_cluster.metric.id
  version     = "1.33"

  scale_policy {
    auto_scale {
      min     = 1
      max     = 3
      initial = 1
    }
  }

  allocation_policy {
    location { zone = local.subnet_a_zone }
  }

  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat        = false
      subnet_ids = [local.subnet_a_id]
    }

    resources {
      memory = 16
      cores  = 4
    }

    boot_disk {
      type = "network-hdd"
      size = 65
    }

    scheduling_policy {
      preemptible = false
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = yandex_kubernetes_cluster.metric.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.metric.master[0].cluster_ca_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]
      command     = "yc"
    }
  }
}

resource "helm_release" "traefik" {
  name             = "traefik"
  chart            = "traefik"
  repository       = "https://traefik.github.io/charts"
  namespace        = "traefik"
  create_namespace = true
  version          = "41.3.0"

  depends_on = [
    yandex_kubernetes_cluster.metric,
    yandex_kubernetes_node_group.k8s_node_group_a
  ]

  values = [
    yamlencode({
      image = {
        registry   = "ghcr.io"
        repository = "traefik/traefik"
      }
      service = {
        spec = {
          type           = "LoadBalancer"
          loadBalancerIP = local.ingress_ip
        }
      }
      # Таймауты для больших загрузок (source maps, debug-файлы).
      ports = {
        web = {
          transport = {
            respondingTimeouts = {
              readTimeout  = "600s"
              writeTimeout = "0s"
            }
          }
        }
        websecure = {
          transport = {
            respondingTimeouts = {
              readTimeout  = "600s"
              writeTimeout = "0s"
            }
          }
        }
      }
    })
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "1.17.1"

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]
  depends_on = [
    yandex_kubernetes_cluster.metric,
    yandex_kubernetes_node_group.k8s_node_group_a
  ]
}

output "k8s_cluster_id" {
  value = yandex_kubernetes_cluster.metric.id
}

output "k8s_cluster_credentials" {
  value = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.metric.id} --external --force"
}

output "ingress_public_ip" {
  value = local.ingress_ip
}

output "metric_fqdn" {
  value = local.metric_fqdn
}

output "metric_url" {
  description = "URL Metric (сформирован через sslip.io из публичного IP балансировщика Traefik)"
  value       = "https://${local.metric_fqdn}"
}
