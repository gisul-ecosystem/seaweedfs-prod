const DEFAULT_PART_SIZE = 8 * 1024 * 1024; // 8 MiB
const MAX_RETRIES = 3;

async function apiPost(path, body) {
  const response = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `Request failed (${response.status})`);
  }
  return payload;
}

function sanitizePrefix(prefix) {
  return prefix.replace(/^\/+|\/+$/g, '');
}

function buildObjectKey(prefix, fileName) {
  const cleanPrefix = sanitizePrefix(prefix);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const safeName = fileName.replace(/[^a-zA-Z0-9._-]+/g, '_');
  const key = cleanPrefix ? `${cleanPrefix}/${stamp}_${safeName}` : `${stamp}_${safeName}`;
  return key;
}

async function uploadPartWithRetry(url, blob, headers, onProgress) {
  let lastError;
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      return await new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open('PUT', url);
        Object.entries(headers || {}).forEach(([name, value]) => {
          if (name.toLowerCase() !== 'host') {
            xhr.setRequestHeader(name, value);
          }
        });
        xhr.upload.onprogress = (event) => {
          if (event.lengthComputable && onProgress) {
            onProgress(event.loaded, event.total);
          }
        };
        xhr.onload = () => {
          if (xhr.status >= 200 && xhr.status < 300) {
            const etag = xhr.getResponseHeader('ETag') || xhr.getResponseHeader('etag');
            resolve(etag);
            return;
          }
          reject(new Error(`Part upload failed with status ${xhr.status}`));
        };
        xhr.onerror = () => reject(new Error('Network error during part upload'));
        xhr.onabort = () => reject(new Error('Part upload aborted'));
        xhr.send(blob);
      });
    } catch (error) {
      lastError = error;
      if (attempt === MAX_RETRIES) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, attempt * 1000));
    }
  }
  throw lastError;
}

export async function uploadFileMultipart({
  file,
  bucket,
  prefix,
  partSize = DEFAULT_PART_SIZE,
  onProgress,
  signal,
}) {
  const key = buildObjectKey(prefix, file.name);
  const init = await apiPost('/api/uploads/init', {
    bucket,
    key,
    contentType: file.type || 'application/octet-stream',
  });

  const parts = [];
  let uploadedBytes = 0;
  const totalParts = Math.ceil(file.size / partSize) || 1;

  try {
    for (let partNumber = 1; partNumber <= totalParts; partNumber++) {
      if (signal?.aborted) {
        throw new Error('Upload cancelled');
      }
      const start = (partNumber - 1) * partSize;
      const end = Math.min(start + partSize, file.size);
      const chunk = file.slice(start, end);

      const presigned = await apiPost('/api/uploads/presign-part', {
        bucket: init.bucket,
        key: init.key,
        uploadId: init.uploadId,
        partNumber,
      });

      const etag = await uploadPartWithRetry(
        presigned.url,
        chunk,
        presigned.headers,
        (loaded) => {
          const current = uploadedBytes + loaded;
          if (onProgress) {
            onProgress(Math.min(current, file.size), file.size);
          }
        },
      );

      uploadedBytes += chunk.size;
      if (onProgress) {
        onProgress(uploadedBytes, file.size);
      }

      parts.push({ partNumber, etag: etag.replaceAll('"', '') });
    }

    const completed = await apiPost('/api/uploads/complete', {
      bucket: init.bucket,
      key: init.key,
      uploadId: init.uploadId,
      parts,
    });

    const signed = await apiPost('/api/uploads/download-url', {
      bucket: init.bucket,
      key: init.key,
      expiresIn: 3600,
    });

    return {
      bucket: init.bucket,
      key: init.key,
      etag: completed.etag,
      downloadUrl: signed.url,
    };
  } catch (error) {
    try {
      await apiPost('/api/uploads/abort', {
        bucket: init.bucket,
        key: init.key,
        uploadId: init.uploadId,
      });
    } catch (_) {
      // best effort abort
    }
    throw error;
  }
}
