#!/bin/sh
set -eu
infile=weed/admin/handlers/admin_handlers.go
outfile=/tmp/admin_handlers.go
awk '{
  print
  if ($0 ~ /filesApi\.Handle\("\/upload", wrapWrite\(h\.fileBrowserHandlers\.UploadFile\)\)\.Methods\(http\.MethodPost\)/) {
    print "\tfilesApi.Handle(\"/upload-init\", wrapWrite(h.fileBrowserHandlers.InitChunkedUpload)).Methods(http.MethodPost)"
    print "\tfilesApi.Handle(\"/upload-chunk\", wrapWrite(h.fileBrowserHandlers.UploadChunk)).Methods(http.MethodPost)"
    print "\tfilesApi.Handle(\"/upload-complete\", wrapWrite(h.fileBrowserHandlers.CompleteChunkedUpload)).Methods(http.MethodPost)"
    print "\tfilesApi.Handle(\"/upload-abort\", wrapWrite(h.fileBrowserHandlers.AbortChunkedUpload)).Methods(http.MethodPost)"
  }
}' "$infile" > "$outfile"
mv "$outfile" "$infile"
grep -n 'upload-init\|upload-chunk\|upload-complete\|upload-abort' "$infile"
