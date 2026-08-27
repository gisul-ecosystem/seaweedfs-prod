#!/bin/bash
set -e
echo "=== CF fetch ==="
curl -sS -D /tmp/cf.hdr -o /tmp/admin.js.cf "https://storage.gisul.co.in/static/js/admin.js"
echo "=== CF HEADERS ==="
head -40 /tmp/cf.hdr
echo "=== CF CHUNK ==="
grep -n "CHUNK_SIZE" /tmp/admin.js.cf | head -5
echo "=== LOCAL fetch ==="
curl -sS -D /tmp/local.hdr -o /tmp/admin.js.local "http://127.0.0.1:23646/static/js/admin.js"
echo "=== LOCAL HEADERS ==="
head -30 /tmp/local.hdr
echo "=== LOCAL CHUNK ==="
grep -n "CHUNK_SIZE" /tmp/admin.js.local | head -5
echo "=== MD5 ==="
md5sum /tmp/admin.js.cf /tmp/admin.js.local
echo "=== BINARY STRINGS ==="
docker exec seaweed-admin sh -c "strings /usr/bin/weed | grep -F 'CHUNK_SIZE =' | head -10"
echo "=== nginx cache? ==="
grep -R "proxy_cache\|expires\|Cache-Control" /etc/nginx/sites-enabled/storage.gisul.co.in /etc/nginx/nginx.conf 2>/dev/null | head -20 || true
echo DONE
