# Развёртывание Metric в Yandex Cloud на Kubernetes

## Введение

[Metric](https://github.com/biosshot/metric) — Sentry-совместимая платформа для
отслеживания ошибок и observability, переписанная на Rust. Одно приложение, одна
база данных (MongoDB), измеримая производительность и в разы меньший footprint,
чем у self-hosted Sentry.

Metric работает как альтернатива/замена Sentry:

- **Оставляете официальный Sentry SDK** — меняете только DSN, и Metric начинает
  принимать ошибки, логи, трейсы, релизы, мониторы, метрики и фидбек.
- **Один процесс на Rust** с встроенным UI вместо стека из Sentry + Relay + Snuba
  + Kafka + ClickHouse + PostgreSQL + Redis + воркеров (65 сервисов в официальном
  self-hosted Compose-файле).
- **Минимальный footprint**: профиль Min работает на 1 vCPU / 1 GiB RAM, тогда как
  self-hosted Sentry рекомендует 4 CPU / 16 GB RAM.
- **Приватность**: scrubbing/pseudonymization приватных данных до записи в БД.

В этой статье мы развернём Metric в Kubernetes на Yandex Managed Kubernetes через
Terraform + Helm: инфраструктура (VPC, K8s, Object Storage), ingress-контроллер
Traefik, cert-manager для HTTPS, MongoDB и Metric из официального Helm-чарта.

## Архитектура

| Компонент | Технология | Namespace | Назначение |
|-----------|-----------|-----------|------------|
| Metric | Helm chart `metric` v0.1.6 | `metric` | Приложение (Rust binary + UI) |
| MongoDB | StatefulSet из Helm-чарта Metric | `metric` | База данных |
| Symbolicator | Deployment из Helm-чарта Metric (профиль medium) | `metric` | Символизация нативных крэшей / source maps |
| BlobStore | Yandex Object Storage (S3) | — (внешний) | Артефакты: debug-файлы, source maps |
| Ingress | Traefik + cert-manager (Let's Encrypt) | `traefik`, `cert-manager` | HTTPS-доступ |
| Infra (VPC, K8s, S3) | Terraform (Yandex Cloud provider) | — | Инфраструктура |

> **Профиль medium** (4 vCPU / 8 GiB RAM) выбран как рекомендуемый default: включает
> Symbolicator и retention 90 дней. Helm-чарт Metric поддерживает профили Min / Low /
> Medium / High — подробности в [документации](https://biosshot.github.io/metric/kubernetes).

## Шаг 1. Аутентификация и Terraform

### Требования

- [yc CLI](https://yandex.cloud/ru/docs/cli/) — настроенный и аутентифицированный (`yc init`)
- [Terraform](https://www.terraform.io/) >= 1.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/) и [Helm](https://helm.sh/) >= 3.19

### Подготовка переменных окружения

```bash
export YC_TOKEN=$(yc iam create-token)
export YC_CLOUD_ID=$(yc config get cloud-id)
# YC_FOLDER_ID можно не задавать — Terraform возьмёт folder_id из конфигурации yc,
# либо укажите явно через terraform.tfvars:
# cp terraform.tfvars.example terraform.tfvars
```

### Применение инфраструктуры

```bash
git clone https://github.com/patsevanton/metric-sentry-alternative-yc-k8s
cd metric-sentry-alternative-yc-k8s

terraform init
terraform apply
```

Terraform создаёт:

- VPC с NAT-шлюзом и тремя приватными подсетями (ноды k8s **без публичных IP**);
- regional Managed Kubernetes 1.33 (нода 4 vCPU / 16 GiB, zone A);
- Object Storage бакет для BlobStore;
- ingress-контроллер **Traefik** (LoadBalancer с публичным IP) и **cert-manager**;
- статический публичный IP для балансировщика.

После применения получаем доступ к кластеру:

```bash
yc managed-kubernetes cluster get-credentials --id $(terraform output -raw k8s_cluster_id) --external --force
kubectl get nodes
```

Готовый домен и IP доступны в outputs:

```bash
terraform output metric_fqdn
# metric.84.201.172.10.sslip.io
```

> **sslip.io** — бесплатный wildcard-DNS: `<anything>.<IP>.sslip.io` всегда резолвится
> в `<IP>`. Не требует делегирования доменной зоны, а Let's Encrypt выдаёт валидный
> TLS-сертификат через HTTP-01 challenge.

Для удобства экспортируем домен:

```bash
export METRIC_FQDN=$(terraform output -raw metric_fqdn)
```

## Шаг 2. Секреты Metric и ClusterIssuer

Terraform уже сгенерировал два файла в корне репозитория:

- `metric-secrets.yaml` — K8s Secret `metric-secrets` с `mongo-password`,
  `scrub-hmac-key`, `s3-access-key-id` и `s3-secret-access-key` (используется
  чартом Metric напрямую);
- `secret_for_bucket.yaml` — K8s Secret `metric-s3-credentials` с S3-ключами
  (запасной вариант, если захотите отдельный Secret для S3).

Оба файла содержат секреты и **не коммитятся** (добавлены в `.gitignore`).

```bash
kubectl create namespace metric
kubectl apply -f metric-secrets.yaml
```

> **Важно.** Secret `metric-secrets` чарт Metric использует для подключения к MongoDB
> (ключ `mongo-password`) и к S3 (`s3-access-key-id`, `s3-secret-access-key`), а также
> для HMAC-ключа псевдонимизации (`scrub-hmac-key`). Сохраняйте этот Secret вместе с
> бэкапами БД и блобов — без него не восстановить и не переиспользовать данные.
> Не генерируйте новый Secret при апгрейде существующей установки.

Создаём ClusterIssuer для Let's Encrypt:

```bash
kubectl apply -f cluster-issuer.yaml
kubectl get clusterissuer letsencrypt-prod
# NAME               READY   AGE
# letsencrypt-prod   True    10s
```

## Шаг 3. Установка Metric через Helm

### Helm-чарт Metric

Чарт публикуется как OCI-пакет. Версия чарта, версия приложения и тег образа всегда
совпадают: чарт **0.1.6** = Metric **0.1.6**.

Terraform уже сгенерировал `metric-values.yaml` из шаблона `metric-values.yaml.tpl`
(с подставленным доменом, S3-endpoint и именем бакета).

```bash
helm install metric oci://ghcr.io/biosshot/charts/metric \
  --version 0.1.6 --namespace metric \
  -f metric-values.yaml \
  --wait --timeout 10m
```

Проверяем поды:

```bash
kubectl -n metric get pods
# metric-xxx              1/1  Running
# metric-mongodb-0        1/1  Running
# metric-symbolicator-xxx 2/2  Running
```

Проверяем готовность:

```bash
helm test metric --namespace metric
```

## Шаг 4. Первичная настройка Metric

Откройте Metric в браузере:

```bash
echo "https://$METRIC_FQDN"
```

Либо через локальный туннель:

```bash
kubectl --namespace metric port-forward service/metric 4001:4001
# http://localhost:4001
```

Извлеките одноразовый bootstrap-токен из логов контейнера Metric (токен генерирует
само приложение Metric при первом запуске — мы его не создаём):

```bash
kubectl --namespace metric logs deployment/metric --container metric
```

Найдите `METRIC_BOOTSTRAP_TOKEN=` и скопируйте его значение (держите в тайне).

Затем следуйте [First setup](https://biosshot.github.io/metric/first-setup):

1. Выберите **First setup**.
2. Вставьте `METRIC_BOOTSTRAP_TOKEN`.
3. Введите имя, email, пароль (не менее 12 символов) и название организации.
4. Сохраните **organization ID** — он нужен при входе (email + пароль + org ID).
5. Создайте первый проект и скопируйте DSN со страницы **Connect an SDK**.

## Шаг 5. Подключение SDK

Оставьте официальный Sentry SDK, поменяйте только DSN:

```javascript
Sentry.init({ dsn: "https://<key>@metric.example.com/<project_id>" });
```

Подробнее: [SDK setup](https://biosshot.github.io/metric/sdk-setup).

## Обновление Metric

```bash
helm upgrade metric oci://ghcr.io/biosshot/charts/metric \
  --version <new-metric-version> --namespace metric \
  -f metric-values.yaml --wait --timeout 20m
```

- Обновления используют `Recreate` и ровно одну реплику; во время миграции `/live`
  возвращает 200, а `/ready` — 503.
- Миграции схемы MongoDB выполняются автоматически и необратимы: **не используйте**
  `helm rollback` через поколения схемы. Helm может откатить манифесты, но не миграции БД.
- Перед обновлением сделайте бэкап MongoDB, S3 и Secret `metric-secrets` вместе.

Подробнее: [Update Metric](https://biosshot.github.io/metric/upgrading),
[backup/restore](https://biosshot.github.io/metric/backup-restore).

## Конфигурация

Храните свои переопределения в `metric-values.yaml` и используйте тот же файл при
апгрейдах. Приложение конфигурируется через секцию `config`, которая мержится поверх
профиля (medium). Например, retention:

```yaml
config:
  retention:
    events_days: 120
```

> Не кладите литеральные секреты в `config` или `--set`. Используйте
> `secrets.existingSecret` и существующие Secret-ы. Слушатель, роль, MongoDB URI,
> HMAC-ключ и подключения BlobStore/Symbolicator управляются чартом и не переопределяются
> в `config`.

Полный список настроек: [Configuration](https://biosshot.github.io/metric/configuration).

## Удаление

```bash
helm uninstall metric --namespace metric --wait
```

PVC MongoDB и Secret-ы сохраняются (аннотация `helm.sh/resource-policy: keep`).
Helm release history — не бэкап данных. Не удаляйте namespace `metric`, иначе
Kubernetes удалит PVC и Secret несмотря на retention-аннотации Helm.

## Полезные ссылки

- [Документация Metric](https://biosshot.github.io/metric/)
- [Kubernetes and Helm](https://biosshot.github.io/metric/kubernetes)
- [Capacity and profiles](https://biosshot.github.io/metric/capacity)
- [Known limits](https://biosshot.github.io/metric/known-limits)
