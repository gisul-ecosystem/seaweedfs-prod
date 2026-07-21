#!/usr/bin/env bash
set -euo pipefail

STORAGE_URL="${STORAGE_URL:-https://storage.gisul.co.in}"
S3API_URL="${S3API_URL:-https://s3api.gisul.co.in}"
UPLOAD_URL="${UPLOAD_URL:-https://upload.gisul.co.in}"

echo "== Health checks =="
curl -fsS "${UPLOAD_URL}/health" | grep -q '"status":"ok"'
curl -fsSI "${S3API_URL}" >/dev/null
curl -fsSI "${STORAGE_URL}" >/dev/null

echo "== Admin JS should not contain hardcoded 500MB cap =="
ADMIN_JS="$(curl -fsS "${STORAGE_URL}/static/js/admin.js")"
if echo "${ADMIN_JS}" | grep -q '500MB limit'; then
  echo "FAIL: admin.js still contains 500MB limit"
  exit 1
fi

echo "== nginx storage config should allow large uploads =="
if [ -f /etc/nginx/sites-available/storage.gisul.co.in ]; then
  grep -q 'client_max_body_size 0;' /etc/nginx/sites-available/storage.gisul.co.in
fi

echo "== Multipart API init smoke test =="
TMP_FILE="$(mktemp)"
head -c 1048576 /dev/zero > "${TMP_FILE}" 2>/dev/null || dd if=/dev/zero of="${TMP_FILE}" bs=1M count=1 2>/dev/null
KEY="smoke/$(date +%s)/test.bin"

INIT_PAYLOAD="$(curl -fsS -X POST "${UPLOAD_URL}/api/uploads/init" \
  -H 'Content-Type: application/json' \
  -d "{\"bucket\":\"videos\",\"key\":\"${KEY}\",\"contentType\":\"application/octet-stream\"}")"

UPLOAD_ID="$(echo "${INIT_PAYLOAD}" | sed -n 's/.*"uploadId":"\([^"]*\)".*/\1/p')"
if [ -z "${UPLOAD_ID}" ]; then
  echo "FAIL: init did not return uploadId"
  echo "${INIT_PAYLOAD}"
  exit 1
fi

PRESIGN_PAYLOAD="$(curl -fsS -X POST "${UPLOAD_URL}/api/uploads/presign-part" \
  -H 'Content-Type: application/json' \
  -d "{\"bucket\":\"videos\",\"key\":\"${KEY}\",\"uploadId\":\"${UPLOAD_ID}\",\"partNumber\":1}")"

PART_URL="$(echo "${PRESIGN_PAYLOAD}" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
ETAG="$(curl -fsSI -X PUT --data-binary @"${TMP_FILE}" "${PART_URL}" | awk 'tolower($1)=="etag:" {print $2}' | tr -d '\r')"
if [ -z "${ETAG}" ]; then
  echo "FAIL: part upload did not return ETag"
  exit 1
fi

curl -fsS -X POST "${UPLOAD_URL}/api/uploads/complete" \
  -H 'Content-Type: application/json' \
  -d "{\"bucket\":\"videos\",\"key\":\"${KEY}\",\"uploadId\":\"${UPLOAD_ID}\",\"parts\":[{\"partNumber\":1,\"etag\":\"${ETAG}\"}]}"

DOWNLOAD_PAYLOAD="$(curl -fsS -X POST "${UPLOAD_URL}/api/uploads/download-url" \
  -H 'Content-Type: application/json' \
  -d "{\"bucket\":\"videos\",\"key\":\"${KEY}\",\"expiresIn\":300}")"

DOWNLOAD_URL="$(echo "${DOWNLOAD_PAYLOAD}" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
curl -fsSI "${DOWNLOAD_URL}" >/dev/null

rm -f "${TMP_FILE}"
echo "PASS: smoke tests completed"
