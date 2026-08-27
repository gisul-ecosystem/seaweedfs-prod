#!/bin/bash
set -euo pipefail
echo '=== UPLOAD ENV SET? ==='
sudo docker inspect gisul-upload-service --format '{{range .Config.Env}}{{println .}}{{end}}' | while IFS='=' read -r k v; do
  case "$k" in
    S3_SECRET_KEY|S3_ACCESS_KEY|ADMIN_PASSWORD)
      echo "$k=SET(len=${#v})"
      ;;
    S3_*|PORT|STATIC_DIR)
      echo "$k=$v"
      ;;
  esac
done

echo '=== TEST INIT ==='
INIT=$(curl -sS -X POST http://127.0.0.1:8088/api/uploads/init \
  -H 'Content-Type: application/json' \
  -d '{"bucket":"videos","key":"test/ci.bin","contentType":"application/octet-stream"}')
echo "$INIT" | python3 -m json.tool || echo "$INIT"

UPLOAD_ID=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("uploadId",""))')
KEY=$(echo "$INIT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))')
if [ -z "$UPLOAD_ID" ]; then
  echo "INIT FAILED"
  exit 0
fi

echo '=== PRESIGN PART ==='
PRES=$(curl -sS -X POST http://127.0.0.1:8088/api/uploads/presign-part \
  -H 'Content-Type: application/json' \
  -d "{\"bucket\":\"videos\",\"key\":\"$KEY\",\"uploadId\":\"$UPLOAD_ID\",\"partNumber\":1}")
echo "$PRES" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("has_url=", bool(d.get("url"))); print("url_prefix=", (d.get("url") or "")[:120]); print("error=", d.get("error",""))'
URL=$(echo "$PRES" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("url",""))')

echo '=== PUT PART TO PRESIGNED URL ==='
dd if=/dev/zero bs=1M count=1 of=/tmp/part.bin status=none
set +e
curl -sS -D /tmp/put.headers -o /tmp/put.body -X PUT --data-binary @/tmp/part.bin "$URL"
set -e
head -20 /tmp/put.headers
echo 'BODY:'
head -c 400 /tmp/put.body; echo

echo '=== LIST BUCKETS VIA LOCAL S3 WITH ENV ==='
# Use dockerized aws cli against local s3 with keys from container env
AK=$(sudo docker inspect gisul-upload-service --format '{{range .Config.Env}}{{println .}}{{end}}' | awk -F= '/^S3_ACCESS_KEY=/{print $2}')
SK=$(sudo docker inspect gisul-upload-service --format '{{range .Config.Env}}{{println .}}{{end}}' | awk -F= '/^S3_SECRET_KEY=/{print $2}')
EP=$(sudo docker inspect gisul-upload-service --format '{{range .Config.Env}}{{println .}}{{end}}' | awk -F= '/^S3_ENDPOINT=/{print $2}')
echo "endpoint=$EP access_len=${#AK} secret_len=${#SK}"
AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" aws --endpoint-url "$EP" s3 ls 2>&1 | head -20 || true
AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" aws --endpoint-url http://127.0.0.1:8333 s3 ls 2>&1 | head -20 || true
