import { uploadFileMultipart } from './s3MultipartUpload.js';

const queueEl = document.getElementById('queue');
const completedEl = document.getElementById('completed');
const fileInput = document.getElementById('fileInput');
const dropZone = document.getElementById('dropZone');
const uploadBtn = document.getElementById('uploadBtn');
const bucketInput = document.getElementById('bucket');
const prefixInput = document.getElementById('prefix');

const jobs = new Map();

function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const index = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / (1024 ** index)).toFixed(2)} ${units[index]}`;
}

function createJobRow(file) {
  const id = `${file.name}-${file.size}-${file.lastModified}`;
  const row = document.createElement('div');
  row.className = 'file-row';
  row.dataset.jobId = id;
  row.innerHTML = `
    <div><strong>${file.name}</strong></div>
    <div class="meta">${formatBytes(file.size)}</div>
    <div class="progress"><span></span></div>
    <div class="meta status">Queued</div>
  `;
  queueEl.prepend(row);
  jobs.set(id, { file, row, controller: null });
  return id;
}

function updateJob(id, percent, status, isError = false) {
  const job = jobs.get(id);
  if (!job) return;
  const bar = job.row.querySelector('.progress > span');
  const statusEl = job.row.querySelector('.status');
  bar.style.width = `${percent}%`;
  statusEl.textContent = status;
  statusEl.className = `meta status${isError ? ' error' : ''}`;
}

function renderCompleted(result) {
  const row = document.createElement('div');
  row.className = 'file-row';
  row.innerHTML = `
    <div><strong>${result.key}</strong></div>
    <div class="meta">Bucket: ${result.bucket}</div>
    <div class="link-row">
      <input type="text" readonly value="${result.downloadUrl}" />
      <button type="button">Copy</button>
      <a href="${result.downloadUrl}" target="_blank" rel="noopener">Open</a>
    </div>
  `;
  row.querySelector('button').addEventListener('click', async () => {
    await navigator.clipboard.writeText(result.downloadUrl);
  });
  completedEl.prepend(row);
}

async function runUpload(file) {
  const id = createJobRow(file);
  const controller = new AbortController();
  jobs.get(id).controller = controller;
  uploadBtn.disabled = true;

  try {
    updateJob(id, 0, 'Uploading...');
    const result = await uploadFileMultipart({
      file,
      bucket: bucketInput.value.trim(),
      prefix: prefixInput.value.trim(),
      signal: controller.signal,
      onProgress: (loaded, total) => {
        const percent = total ? Math.round((loaded / total) * 100) : 0;
        updateJob(id, percent, `Uploading ${percent}%`);
      },
    });
    updateJob(id, 100, 'Completed');
    renderCompleted(result);
  } catch (error) {
    updateJob(id, 0, error.message || 'Upload failed', true);
  } finally {
    uploadBtn.disabled = false;
  }
}

function collectFiles() {
  return Array.from(fileInput.files || []);
}

uploadBtn.addEventListener('click', async () => {
  const files = collectFiles();
  if (!files.length) {
    alert('Select at least one file');
    return;
  }
  for (const file of files) {
    await runUpload(file);
  }
});

['dragenter', 'dragover'].forEach((eventName) => {
  dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.classList.add('drag-over');
  });
});

['dragleave', 'drop'].forEach((eventName) => {
  dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.classList.remove('drag-over');
  });
});

dropZone.addEventListener('drop', (event) => {
  const files = Array.from(event.dataTransfer.files || []);
  if (!files.length) return;
  const dt = new DataTransfer();
  files.forEach((file) => dt.items.add(file));
  fileInput.files = dt.files;
});
