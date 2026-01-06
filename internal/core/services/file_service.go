package services

import (
	"context"
	"fmt"
	"log"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type FileService struct {
	minioClient *minio.Client
	bucketName  string
	publicURL   string
	isEnabled   bool
}

func NewFileService() *FileService {
	// 1. Configuración
	endpoint := os.Getenv("MINIO_ENDPOINT")
	accessKeyID := os.Getenv("MINIO_ACCESS_KEY")
	secretAccessKey := os.Getenv("MINIO_SECRET_KEY")
	bucketName := os.Getenv("MINIO_BUCKET")
	useSSL := os.Getenv("MINIO_USE_SSL") == "true"
	publicURL := os.Getenv("STORAGE_PUBLIC_URL")

	if endpoint == "" || accessKeyID == "" {
		log.Println("ADVERTENCIA: Variables de MinIO incompletas. Servicio desactivado.")
		return &FileService{isEnabled: false}
	}

	// 2. Conexión
	minioClient, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKeyID, secretAccessKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		log.Printf("Error conectando a MinIO: %v. Servicio desactivado.\n", err)
		return &FileService{isEnabled: false}
	}

	// 3. Setup del Bucket
	ctx := context.Background()
	exists, err := minioClient.BucketExists(ctx, bucketName)
	if err != nil {
		log.Printf("Error verificando bucket '%s': %v.\n", bucketName, err)
		return &FileService{isEnabled: false}
	} 
	
	if !exists {
		err = minioClient.MakeBucket(ctx, bucketName, minio.MakeBucketOptions{})
		if err != nil {
			log.Printf("Error creando bucket: %v\n", err)
			return &FileService{isEnabled: false}
		}
		log.Printf("Bucket '%s' creado exitosamente.\n", bucketName)
	}

	// --- CORRECCIÓN CLAVE: SIEMPRE APLICAR POLÍTICA PÚBLICA ---
	// No importa si el bucket es nuevo o viejo, refrescamos los permisos de lectura.
	policy := fmt.Sprintf(`{
		"Version": "2012-10-17",
		"Statement": [
			{
				"Action": ["s3:GetObject"],
				"Effect": "Allow",
				"Principal": {"AWS": ["*"]},
				"Resource": ["arn:aws:s3:::%s/*"]
			}
		]
	}`, bucketName)

	err = minioClient.SetBucketPolicy(ctx, bucketName, policy)
	if err != nil {
		log.Printf("Error configurando política pública en bucket: %v\n", err)
	} else {
		log.Printf("Política de acceso público configurada para '%s'.\n", bucketName)
	}
	// -----------------------------------------------------------

	return &FileService{
		minioClient: minioClient,
		bucketName:  bucketName,
		publicURL:   publicURL,
		isEnabled:   true,
	}
}

// SaveImage sube el archivo
func (s *FileService) SaveImage(ctx context.Context, file *multipart.FileHeader) (string, error) {
	if !s.isEnabled || s.minioClient == nil {
		return "", fmt.Errorf("servicio de almacenamiento no disponible")
	}

	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		return "", fmt.Errorf("formato inválido (solo JPG/PNG)")
	}

	objectName := uuid.New().String() + ext
	contentType := file.Header.Get("Content-Type")

	src, err := file.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	_, err = s.minioClient.PutObject(ctx, s.bucketName, objectName, src, file.Size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		log.Printf("Error MinIO PutObject: %v", err) // Log extra para debug
		return "", fmt.Errorf("error subiendo a Storage: %v", err)
	}

	return fmt.Sprintf("%s/%s/%s", s.publicURL, s.bucketName, objectName), nil
}

// SaveMultipleImages reutiliza SaveImage
func (s *FileService) SaveMultipleImages(ctx context.Context, files []*multipart.FileHeader) ([]string, error) {
	var urls []string
	for _, file := range files {
		url, err := s.SaveImage(ctx, file)
		if err != nil {
			log.Printf("Error subiendo una de las imágenes: %v", err)
			continue
		}
		urls = append(urls, url)
	}
	return urls, nil
}