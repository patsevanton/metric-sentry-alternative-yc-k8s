apiVersion: v1
kind: Secret
metadata:
  name: metric-secrets
  namespace: metric
type: Opaque
stringData:
  mongo-password: ${mongo_password}
  scrub-hmac-key: ${scrub_hmac_key}
  s3-access-key-id: ${s3_access_key}
  s3-secret-access-key: ${s3_secret_key}
