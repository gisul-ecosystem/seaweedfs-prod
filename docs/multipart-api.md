# Multipart Upload API

Base URL: `https://upload.gisul.co.in`

All endpoints accept and return JSON.

## POST /api/uploads/init

Create a multipart upload.

Request:
```json
{
  "bucket": "videos",
  "key": "transfer/demo.bin",
  "contentType": "application/octet-stream"
}
```

Response:
```json
{
  "bucket": "videos",
  "key": "transfer/demo.bin",
  "uploadId": "..."
}
```

## POST /api/uploads/presign-part

Get a presigned URL for one upload part.

Request:
```json
{
  "bucket": "videos",
  "key": "transfer/demo.bin",
  "uploadId": "...",
  "partNumber": 1
}
```

Response:
```json
{
  "url": "https://s3api.gisul.co.in/...",
  "method": "PUT",
  "headers": {},
  "partNumber": 1
}
```

## POST /api/uploads/complete

Complete multipart upload.

Request:
```json
{
  "bucket": "videos",
  "key": "transfer/demo.bin",
  "uploadId": "...",
  "parts": [
    { "partNumber": 1, "etag": "..." }
  ]
}
```

## POST /api/uploads/abort

Abort a failed multipart upload.

## POST /api/uploads/download-url

Generate a signed GET link for private download.

Request:
```json
{
  "bucket": "videos",
  "key": "transfer/demo.bin",
  "expiresIn": 3600
}
```

Response:
```json
{
  "url": "https://s3api.gisul.co.in/...",
  "method": "GET",
  "expiresIn": 3600
}
```
