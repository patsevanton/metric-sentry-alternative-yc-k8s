# Секреты Metric (mongo-password, scrub-hmac-key) генерируются Terraform и
# рендерятся в k8s Secret `metric-secrets`. Храните этот файл вместе с бэкапами
# MongoDB и S3-блобов. НЕ коммитьте сгенерированный файл.
resource "random_password" "mongo_password" {
  length  = 24
  special = false
}

resource "random_password" "scrub_hmac_key" {
  length  = 32
  special = false
}

resource "local_file" "metric_secrets" {
  content = templatefile("${path.module}/metric-secrets.yaml.tpl", {
    mongo_password = random_password.mongo_password.result
    scrub_hmac_key = random_password.scrub_hmac_key.result
    s3_access_key  = yandex_iam_service_account_static_access_key.sa_storage_admin_static_key.access_key
    s3_secret_key  = yandex_iam_service_account_static_access_key.sa_storage_admin_static_key.secret_key
  })
  filename = "${path.module}/metric-secrets.yaml"
}
