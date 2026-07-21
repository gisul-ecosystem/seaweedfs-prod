package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type cfg struct {
	Port          string
	S3Endpoint    string
	S3Region      string
	S3AccessKey   string
	S3SecretKey   string
	DefaultBucket string
	StaticDir     string
	URLExpiry     time.Duration
}

type server struct {
	s3Client      *s3.Client
	presignClient *s3.PresignClient
	cfg           cfg
}

func loadConfig() cfg {
	expiry := 15 * time.Minute
	if v := os.Getenv("PRESIGN_EXPIRY_SECONDS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			expiry = time.Duration(n) * time.Second
		}
	}
	return cfg{
		Port:          envOr("PORT", "8088"),
		S3Endpoint:    envOr("S3_ENDPOINT", "https://s3api.gisul.co.in"),
		S3Region:      envOr("S3_REGION", "us-east-1"),
		S3AccessKey:   os.Getenv("S3_ACCESS_KEY"),
		S3SecretKey:   os.Getenv("S3_SECRET_KEY"),
		DefaultBucket: envOr("S3_DEFAULT_BUCKET", "videos"),
		StaticDir:     envOr("STATIC_DIR", "../upload-portal"),
		URLExpiry:     expiry,
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func newServer(c cfg) (*server, error) {
	if c.S3AccessKey == "" || c.S3SecretKey == "" {
		return nil, fmt.Errorf("S3_ACCESS_KEY and S3_SECRET_KEY are required")
	}
	awsCfg, err := config.LoadDefaultConfig(context.Background(),
		config.WithRegion(c.S3Region),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(c.S3AccessKey, c.S3SecretKey, "")),
	)
	if err != nil {
		return nil, err
	}
	client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		// Path-style URLs: https://s3api.../bucket/key
		// Do NOT override EndpointResolverV2 — that drops the bucket from the path.
		o.BaseEndpoint = aws.String(c.S3Endpoint)
		o.UsePathStyle = true
	})
	return &server{
		s3Client:      client,
		presignClient: s3.NewPresignClient(client),
		cfg:           c,
	}, nil
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func (s *server) bucketOrDefault(bucket string) string {
	if strings.TrimSpace(bucket) != "" {
		return bucket
	}
	return s.cfg.DefaultBucket
}

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type initRequest struct {
	Bucket      string `json:"bucket"`
	Key         string `json:"key"`
	ContentType string `json:"contentType"`
}

func (s *server) handleInit(w http.ResponseWriter, r *http.Request) {
	var req initRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if strings.TrimSpace(req.Key) == "" {
		writeError(w, http.StatusBadRequest, "key is required")
		return
	}
	bucket := s.bucketOrDefault(req.Bucket)
	input := &s3.CreateMultipartUploadInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(req.Key),
	}
	if req.ContentType != "" {
		input.ContentType = aws.String(req.ContentType)
	}
	out, err := s.s3Client.CreateMultipartUpload(r.Context(), input)
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"bucket":   bucket,
		"key":      req.Key,
		"uploadId": aws.ToString(out.UploadId),
	})
}

type presignPartRequest struct {
	Bucket     string `json:"bucket"`
	Key        string `json:"key"`
	UploadID   string `json:"uploadId"`
	PartNumber int32  `json:"partNumber"`
}

func (s *server) handlePresignPart(w http.ResponseWriter, r *http.Request) {
	var req presignPartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.UploadID == "" || req.PartNumber <= 0 || strings.TrimSpace(req.Key) == "" {
		writeError(w, http.StatusBadRequest, "uploadId, key, and partNumber are required")
		return
	}
	bucket := s.bucketOrDefault(req.Bucket)
	out, err := s.presignClient.PresignUploadPart(r.Context(), &s3.UploadPartInput{
		Bucket:     aws.String(bucket),
		Key:        aws.String(req.Key),
		UploadId:   aws.String(req.UploadID),
		PartNumber: aws.Int32(req.PartNumber),
	}, s3.WithPresignExpires(s.cfg.URLExpiry))
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"url":        out.URL,
		"method":     out.Method,
		"headers":    out.SignedHeader,
		"partNumber": req.PartNumber,
	})
}

type completedPart struct {
	PartNumber int32  `json:"partNumber"`
	ETag       string `json:"etag"`
}

type completeRequest struct {
	Bucket   string          `json:"bucket"`
	Key      string          `json:"key"`
	UploadID string          `json:"uploadId"`
	Parts    []completedPart `json:"parts"`
}

func (s *server) handleComplete(w http.ResponseWriter, r *http.Request) {
	var req completeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.UploadID == "" || strings.TrimSpace(req.Key) == "" || len(req.Parts) == 0 {
		writeError(w, http.StatusBadRequest, "uploadId, key, and parts are required")
		return
	}
	bucket := s.bucketOrDefault(req.Bucket)
	parts := make([]types.CompletedPart, 0, len(req.Parts))
	for _, p := range req.Parts {
		parts = append(parts, types.CompletedPart{
			ETag:       aws.String(strings.Trim(p.ETag, "\"")),
			PartNumber: aws.Int32(p.PartNumber),
		})
	}
	out, err := s.s3Client.CompleteMultipartUpload(r.Context(), &s3.CompleteMultipartUploadInput{
		Bucket:   aws.String(bucket),
		Key:      aws.String(req.Key),
		UploadId: aws.String(req.UploadID),
		MultipartUpload: &types.CompletedMultipartUpload{
			Parts: parts,
		},
	})
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"bucket": bucket,
		"key":    req.Key,
		"etag":   aws.ToString(out.ETag),
		"location": aws.ToString(out.Location),
	})
}

type abortRequest struct {
	Bucket   string `json:"bucket"`
	Key      string `json:"key"`
	UploadID string `json:"uploadId"`
}

func (s *server) handleAbort(w http.ResponseWriter, r *http.Request) {
	var req abortRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.UploadID == "" || strings.TrimSpace(req.Key) == "" {
		writeError(w, http.StatusBadRequest, "uploadId and key are required")
		return
	}
	bucket := s.bucketOrDefault(req.Bucket)
	_, err := s.s3Client.AbortMultipartUpload(r.Context(), &s3.AbortMultipartUploadInput{
		Bucket:   aws.String(bucket),
		Key:      aws.String(req.Key),
		UploadId: aws.String(req.UploadID),
	})
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "aborted"})
}

type downloadURLRequest struct {
	Bucket    string `json:"bucket"`
	Key       string `json:"key"`
	ExpiresIn int32  `json:"expiresIn"`
}

func (s *server) handleDownloadURL(w http.ResponseWriter, r *http.Request) {
	var req downloadURLRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if strings.TrimSpace(req.Key) == "" {
		writeError(w, http.StatusBadRequest, "key is required")
		return
	}
	bucket := s.bucketOrDefault(req.Bucket)
	expiry := s.cfg.URLExpiry
	if req.ExpiresIn > 0 {
		expiry = time.Duration(req.ExpiresIn) * time.Second
	}
	out, err := s.presignClient.PresignGetObject(r.Context(), &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(req.Key),
	}, s3.WithPresignExpires(expiry))
	if err != nil {
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"url":       out.URL,
		"method":    out.Method,
		"expiresIn": int(expiry.Seconds()),
	})
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	c := loadConfig()
	srv, err := newServer(c)
	if err != nil {
		log.Fatalf("startup failed: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", srv.handleHealth)
	mux.HandleFunc("/api/uploads/init", srv.handleInit)
	mux.HandleFunc("/api/uploads/presign-part", srv.handlePresignPart)
	mux.HandleFunc("/api/uploads/complete", srv.handleComplete)
	mux.HandleFunc("/api/uploads/abort", srv.handleAbort)
	mux.HandleFunc("/api/uploads/download-url", srv.handleDownloadURL)

	staticDir, err := filepath.Abs(c.StaticDir)
	if err == nil {
		mux.Handle("/", http.FileServer(http.Dir(staticDir)))
	}

	addr := ":" + c.Port
	log.Printf("upload service listening on %s (S3 endpoint %s)", addr, c.S3Endpoint)
	if err := http.ListenAndServe(addr, withCORS(mux)); err != nil {
		log.Fatal(err)
	}
}
