# Инструкция для AI-агента / LLM

## Контекст проекта

Этот репозиторий разворачивает [Metric](https://github.com/biosshot/metric) — Sentry-совместимую
observability-платформу на Rust — в Kubernetes на Yandex Cloud через Terraform + Helm.
Подробное описание всех шагов и команд — в [README.md](README.md).

## Архитектура

| Компонент | Технология | Namespace | Где управляется |
|-----------|-----------|-----------|-----------------|
| Metric | Helm chart `metric` v0.1.6 (OCI) | `metric` | `metric-values.yaml.tpl`, `ip-dns.tf` |
| MongoDB | StatefulSet из чарта Metric | `metric` | `metric-values.yaml.tpl` |
| Symbolicator | Deployment из чарта Metric (medium) | `metric` | `metric-values.yaml.tpl` |
| BlobStore | Yandex Object Storage (S3) | — (внешний) | `s3.tf` |
| Ingress | Traefik + cert-manager | `traefik`, `cert-manager` | `k8s.tf`, `cluster-issuer.yaml` |
| Infra (VPC, K8s, S3) | Terraform (Yandex Cloud provider) | — | `*.tf` в корне |

## Ключевые файлы

| Файл | Назначение | Когда менять |
|------|-----------|--------------|
| `metric-values.yaml.tpl` | Шаблон Helm values для Metric | При изменении конфигурации Metric, профиля, S3, ingress |
| `metric-values.yaml` | Сгенерированный Helm values | **НЕ редактировать** — генерируется `ip-dns.tf` |
| `metric-secrets.yaml.tpl` | Шаблон Secret (mongo-password, scrub-hmac-key, S3) | При изменении состава секретов |
| `metric-secrets.yaml` | Сгенерированный Secret | **НЕ коммитить**, генерируется `secrets.tf` |
| `secret_for_bucket.yaml` | Сгенерированный S3 Secret | **НЕ коммитить**, генерируется `s3.tf` |
| `cluster-issuer.yaml` | ClusterIssuer Let's Encrypt | При изменении email/класса ingress |
| `*.tf` (корень) | Terraform-ресурсы (VPC, K8s, S3) | При изменении инфраструктуры |

## Порядок развёртывания

1. `terraform init && terraform apply` — создаёт VPC, K8s, S3, Traefik, cert-manager,
   а также рендерит `metric-values.yaml`, `metric-secrets.yaml`, `secret_for_bucket.yaml`.
2. `kubectl create namespace metric` + `kubectl apply -f metric-secrets.yaml` — Secret.
3. `kubectl apply -f cluster-issuer.yaml` — ClusterIssuer `letsencrypt-prod`.
4. `helm install metric oci://ghcr.io/biosshot/charts/metric --version 0.1.6 -n metric -f metric-values.yaml` — Metric.
5. Извлечь `METRIC_BOOTSTRAP_TOKEN` из логов и пройти first setup.
   Токен генерирует само приложение Metric при первом запуске (мы его не создаём):
   ```bash
   kubectl --namespace metric logs deployment/metric --container metric
   ```
   Найти строку `METRIC_BOOTSTRAP_TOKEN=` и скопировать её значение (держать в тайне).

## CRITICAL RULES — ОБЯЗАТЕЛЬНО

- **Инфраструктурные правила** (общие для всех проектов):
  - ноды k8s **без публичных IP** (`nat = false`), исходящий трафик через NAT-шлюз + route table;
  - обновлять компоненты инфраструктуры, кроме k8s и ingress-nginx; версии k8s и
    ingress-nginx не менять без явного указания (здесь используется Traefik — не меняй
    его версию без явного запроса).
- НЕ коммитить секреты/токены: `metric-values.yaml`, `metric-secrets.yaml`,
  `secret_for_bucket.yaml`, `terraform.tfstate` — в `.gitignore`.
- НЕ запрашивать IAM-токен Yandex Cloud у пользователя (чувствительный секрет).
- ALWAYS проверять `terraform plan` перед `terraform apply`.
- Миграции схемы MongoDB у Metric необратимы: НЕ делать `helm rollback` через поколения
  схемы; НЕ удалять БД/PVC/Secret для обхода ошибки версии.
- Secret `metric-secrets` НЕ пересоздавать при апгрейде существующих данных.
- Одна задача за раз. Если не уверен — СПРОСИ, не угадывай.

## Стиль работы

- Сначала ПЛАН, потом код.
- Маленькие дифы: один файл → проверка → следующий файл.
- Terraform: проверяй зависимости между ресурсами перед изменением.
- Helm values: сверяйся с `metric-values.yaml.tpl` и [документацией чарта](https://biosshot.github.io/metric/kubernetes).

## Ссылки

- Документация Metric: https://biosshot.github.io/metric/
- Kubernetes and Helm: https://biosshot.github.io/metric/kubernetes
- Configuration: https://biosshot.github.io/metric/configuration
- Upgrading: https://biosshot.github.io/metric/upgrading
