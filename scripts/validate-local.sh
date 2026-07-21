#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "== Source checks =="
if grep -q '500MB limit' "${ROOT}/weed/admin/static/js/admin.js"; then
  echo "FAIL: admin.js still contains 500MB limit"
  exit 1
fi

echo "== Build upload-service =="
(cd "${ROOT}/deploy/gisul/upload-service" && go build -o /tmp/gisul-upload-service .)

echo "== Required deploy files =="
for f in \
  deploy/gisul/docker-compose.yml \
  deploy/gisul/nginx/storage.gisul.co.in.conf \
  deploy/gisul/nginx/s3api.gisul.co.in.conf \
  deploy/gisul/nginx/upload.gisul.co.in.conf \
  deploy/gisul/scripts/smoke-test.sh \
  .github/workflows/deploy-gisul.yml; do
  test -f "${ROOT}/${f}"
done

echo "PASS: local validation completed"
echo "NOTE: run deploy/gisul/scripts/smoke-test.sh after VM deployment"
