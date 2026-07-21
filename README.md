# Gisul SeaweedFS production deploy

Clean deploy-only repository for `103.99.38.219`.

This repo does **not** contain the full upstream SeaweedFS source.
The CI build clones official SeaweedFS and applies Gisul admin patches.

## Contents

- `docker-compose.yml` — master, volume, filer, s3, admin, upload-service
- `upload-service/` + `upload-portal/` — large multipart uploads + signed links
- `nginx/` — storage / s3api / upload site configs
- `patches/` — admin UI 500MB-limit removal and handler tweak
- `.github/workflows/deploy-gisul.yml` — only CI workflow

## Required GitHub secrets

- `VM_HOST`
- `VM_USER`
- `VM_SSH_KEY`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`
- `S3_DEFAULT_BUCKET`
- `ADMIN_PASSWORD`

## Deploy

Push to `main` or run **Deploy SeaweedFS Prod** from Actions.
