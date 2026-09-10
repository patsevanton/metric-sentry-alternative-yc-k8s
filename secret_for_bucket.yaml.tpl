apiVersion: v1
kind: Secret
metadata:
  name: metric-s3-credentials
  namespace: metric
type: Opaque
stringData:
  s3-access-key-id: ${access_key}
  s3-secret-access-key: ${secret_key}
