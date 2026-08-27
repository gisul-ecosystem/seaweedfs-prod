#!/bin/bash
echo "=== admin / docker ==="
docker inspect seaweed-admin --format 'image={{.Config.Image}} started={{.State.StartedAt}}'
echo "=== disk / tmp ==="
df -h / /tmp 2>/dev/null | head -5
docker exec seaweed-admin sh -c 'df -h /tmp 2>/dev/null; ls -lah /tmp/seaweedfs-admin-uploads 2>/dev/null | head -20; du -sh /tmp/seaweedfs-admin-uploads 2>/dev/null || true'
echo "=== recent admin logs ==="
docker logs --tail 40 seaweed-admin 2>&1 | tail -40
echo "=== nginx timeouts / buffering ==="
grep -E 'client_max_body|proxy_buffer|timeout|proxy_request' /etc/nginx/sites-available/storage.gisul.co.in
echo "=== cloudflare on storage? ==="
curl -sSI https://storage.gisul.co.in/ | grep -iE 'server:|cf-ray|cf-cache|HTTP/'
echo DONE
