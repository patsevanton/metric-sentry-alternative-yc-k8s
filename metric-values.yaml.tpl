# Metric v0.1.6 — Helm values, генерируется из metric-values.yaml.tpl через Terraform.
# Профиль medium: Metric + MongoDB + Symbolicator, BlobStore на Yandex Object Storage (S3).
profile: medium

secrets:
  existingSecret: metric-secrets

service:
  type: ClusterIP
  port: 4001

ingress:
  enabled: true
  className: traefik
  host: ${fqdn}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
  tls:
    - secretName: metric-tls
      hosts:
        - ${fqdn}

http:
  # HTTPS ставится перед Metric через Traefik, поэтому secure-куки включаем.
  secureCookies: true
  # CIDR подов кластера — Traefik (ingress-контроллер) живёт в этой сети.
  # Yandex Managed Kubernetes — VPC-native: поды получают IP из подсетей нод
  # (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24).
  trustedProxies:
    - 10.0.0.0/16

blob:
  backend: s3
  s3:
    endpoint: ${s3_endpoint}
    region: ${s3_region}
    bucket: ${s3_bucket}
    forcePathStyle: true
    existingSecret: metric-secrets

mongodb:
  enabled: true
  database: metric
  persistence:
    size: 30Gi

persistence:
  # При backend=s3 локальный BlobStore PVC не создаётся; значение игнорируется.
  size: ""

# Дополнительно можно переопределить retention, ресурсы и т.п. через секцию config.
config: {}
