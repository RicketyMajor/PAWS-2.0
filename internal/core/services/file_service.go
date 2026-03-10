// Package services contains the core business logic of the application.
package services

import (
	"context"
	"fmt"
	"log"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"

	"github.com/cloudinary/cloudinary-go/v2"
	"github.com/cloudinary/cloudinary-go/v2/api"
	"github.com/cloudinary/cloudinary-go/v2/api/uploader"
	"github.com/google/uuid"
)

// =========================================================================
// Service Definition
// =========================================================================

// FileService handles file uploads, currently using Cloudinary as the storage provider.
type FileService struct {
	cld       *cloudinary.Cloudinary
	isEnabled bool
}

// NewFileService creates a new FileService and connects to Cloudinary if the URL is provided.
func NewFileService() *FileService {
	cldURL := os.Getenv("CLOUDINARY_URL")

	if cldURL == "" {
		log.Println("WARNING: CLOUDINARY_URL not found. File service is disabled; images will not be saved.")
		return &FileService{isEnabled: false}
	}

	cld, err := cloudinary.NewFromURL(cldURL)
	if err != nil {
		log.Printf("Error initializing Cloudinary: %v. File service is disabled.\n", err)
		return &FileService{isEnabled: false}
	}

	log.Println("Storage service (Cloudinary) connected successfully.")
	return &FileService{
		cld:       cld,
		isEnabled: true,
	}
}

// =========================================================================
// Service Methods
// =========================================================================

// SaveImage uploads a single image file to Cloudinary and returns its secure URL.
func (s *FileService) SaveImage(ctx context.Context, file *multipart.FileHeader) (string, error) {
	if !s.isEnabled {
		return "", fmt.Errorf("storage service is not available")
	}

	// Validate file extension.
	ext := strings.ToLower(filepath.Ext(file.Filename))
	validExtensions := map[string]bool{
		".jpg": true, ".jpeg": true, ".png": true,
		".webp": true, ".heic": true, ".heif": true,
	}
	if !validExtensions[ext] {
		return "", fmt.Errorf("invalid format %s. Allowed formats: JPG, PNG, WEBP, HEIC", ext)
	}

	src, err := file.Open()
	if err != nil {
		return "", fmt.Errorf("error reading file: %v", err)
	}
	defer src.Close()

	// Generate a unique public ID for the file in the cloud.
	uniqueFilename := uuid.New().String()

	// Upload to Cloudinary.
	resp, err := s.cld.Upload.Upload(ctx, src, uploader.UploadParams{
		PublicID:     uniqueFilename,
		Folder:       "paws_uploads",
		ResourceType: "image",
		Overwrite:    api.Bool(true),
	})

	if err != nil {
		log.Printf("Cloudinary Upload Error: %v", err)
		return "", fmt.Errorf("error uploading to cloud storage: %v", err)
	}

	return resp.SecureURL, nil
}

// SaveMultipleImages uploads multiple image files by calling SaveImage for each.
func (s *FileService) SaveMultipleImages(ctx context.Context, files []*multipart.FileHeader) ([]string, error) {
	var urls []string

	if !s.isEnabled {
		return urls, fmt.Errorf("storage service is not available")
	}

	for _, file := range files {
		url, err := s.SaveImage(ctx, file)
		if err != nil {
			log.Printf("Error uploading one of the images (%s): %v", file.Filename, err)
			return nil, err
		}
		urls = append(urls, url)
	}
	return urls, nil
}
