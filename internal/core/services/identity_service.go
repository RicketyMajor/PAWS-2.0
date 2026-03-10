// Package services contains the core business logic of the application.
package services

import (
	"context"
	"fmt"
	"math/rand"
	"mime/multipart"
	"path/filepath"
	"strconv"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// =========================================================================
// Service Definition
// =========================================================================

// IdentityService provides a mock identity verification service.
// It uploads a document to MinIO and returns a randomly generated, valid-looking Chilean RUN.
type IdentityService struct {
	minioClient *minio.Client
	bucketName  string
}

// NewIdentityService creates a new IdentityService and connects to MinIO.
func NewIdentityService() *IdentityService {
    endpoint := "minio-service:9000"
	accessKeyID := "minioadmin"
	secretAccessKey := "minioadmin"
	useSSL := false

	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKeyID, secretAccessKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		fmt.Println("Error connecting to MinIO:", err)
		return nil
	}

	bucketName := "paws-identity"
	ctx := context.Background()
	exists, errBucket := client.BucketExists(ctx, bucketName)
	if errBucket == nil && !exists {
		errCreate := client.MakeBucket(ctx, bucketName, minio.MakeBucketOptions{})
		if errCreate != nil {
			fmt.Println("Error creating bucket automatically:", errCreate)
		} else {
			fmt.Println("Bucket 'paws-identity' created automatically")
		}
	}

	return &IdentityService{
		minioClient: client,
		bucketName:  bucketName,
	}
}

// =========================================================================
// Service Methods
// =========================================================================

// VerifyIdentity uploads the provided document and returns a simulated RUN.
func (s *IdentityService) VerifyIdentity(file *multipart.FileHeader) (string, error) {
	src, err := file.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	// Use a timestamp to avoid filename collisions.
	filename := fmt.Sprintf("id_scan_%d_%s", time.Now().Unix(), filepath.Base(file.Filename))

	ctx := context.Background()
	_, err = s.minioClient.PutObject(ctx, s.bucketName, filename, src, file.Size, minio.PutObjectOptions{
		ContentType: file.Header.Get("Content-Type"),
	})
	if err != nil {
		return "", fmt.Errorf("error uploading document: %v", err)
	}

	// MOCK: Generate a random valid RUN to allow multiple registrations.
	mockRun := s.generateRandomRUN()
	
	return mockRun, nil
}

// =========================================================================
// Helper Functions
// =========================================================================

// generateRandomRUN creates a valid-looking Chilean RUN format (e.g., 12.345.678-K).
func (s *IdentityService) generateRandomRUN() string {
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	
	// Generate a number between 10,000,000 and 25,000,000.
	number := r.Intn(15000000) + 10000000
	
	// Calculate the verifier digit (DV) using the Modulo 11 algorithm.
	dv := calculateDV(number)
	
	return fmt.Sprintf("%s-%s", formatWithPoints(number), dv)
}

// calculateDV implements the Modulo 11 algorithm to calculate the verifier digit.
func calculateDV(rut int) string {
	m := 0
	s := 1
	for rut != 0 {
		s = (s + rut%10*(9-m%6)) % 11
		rut /= 10
		m++
	}
	if s != 0 {
		return strconv.Itoa(s - 1)
	}
	return "K"
}

// formatWithPoints adds dots to an 8-digit number for standard formatting.
func formatWithPoints(n int) string {
	s := strconv.Itoa(n)
	if len(s) == 8 {
		return fmt.Sprintf("%s.%s.%s", s[0:2], s[2:5], s[5:8])
	}
	return s // Fallback for other lengths
}