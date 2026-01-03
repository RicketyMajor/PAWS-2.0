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
	isEnabled   bool // Nueva bandera para saber si está activo
}

func NewFileService() *FileService {
	// 1. Leemos configuración
	endpoint := os.Getenv("MINIO_ENDPOINT")
	accessKeyID := os.Getenv("MINIO_ACCESS_KEY")
	secretAccessKey := os.Getenv("MINIO_SECRET_KEY")
	bucketName := os.Getenv("MINIO_BUCKET")
	useSSL := os.Getenv("MINIO_USE_SSL") == "true"
	publicURL := os.Getenv("STORAGE_PUBLIC_URL")

	// 2. Validación SUAVE (Soft Check)
	// Si no hay endpoint configurado, no crasheamos, solo avisamos.
	if endpoint == "" || accessKeyID == "" {
		log.Println(" ADVERTENCIA: Variables de MinIO incompletas. El servicio de archivos estará DESACTIVADO.")
		return &FileService{isEnabled: false}
	}

	// 3. Inicializar cliente
	minioClient, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKeyID, secretAccessKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		log.Printf(" Error conectando a MinIO: %v. Servicio desactivado.\n", err)
		return &FileService{isEnabled: false}
	}

	// 4. Auto-setup (Crear bucket si no existe)
	// Usamos un timeout corto para no bloquear el arranque si la red falla
	ctx := context.Background()
	exists, err := minioClient.BucketExists(ctx, bucketName)
	if err != nil {
		log.Printf(" No se pudo verificar el bucket '%s': %v. Servicio desactivado.\n", bucketName, err)
		// En producción, esto podría ser temporal, pero por seguridad desactivamos
		return &FileService{isEnabled: false}
	} else if !exists {
		err = minioClient.MakeBucket(ctx, bucketName, minio.MakeBucketOptions{})
		if err != nil {
			log.Printf("Error creando bucket: %v\n", err)
		} else {
			log.Printf("Bucket '%s' creado exitosamente.\n", bucketName)
			// Política pública
			policy := fmt.Sprintf(`{"Version": "2012-10-17","Statement": [{"Action": ["s3:GetObject"],"Effect": "Allow","Principal": {"AWS": ["*"]},"Resource": ["arn:aws:s3:::%s/*"]}]}`, bucketName)
			_ = minioClient.SetBucketPolicy(ctx, bucketName, policy)
		}
	} else {
		log.Printf("Conectado al bucket existente: '%s'\n", bucketName)
	}

	return &FileService{
		minioClient: minioClient,
		bucketName:  bucketName,
		publicURL:   publicURL,
		isEnabled:   true,
	}
}

// SaveImage sube el archivo a MinIO/S3
func (s *FileService) SaveImage(ctx context.Context, file *multipart.FileHeader) (string, error) {
	// 1. Verificar si el servicio está activo
	if !s.isEnabled || s.minioClient == nil {
		return "", fmt.Errorf("el servicio de almacenamiento no está disponible en este entorno")
	}

	// 2. Validar extensión
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		return "", fmt.Errorf("formato no permitido (solo JPG/PNG)")
	}

	// 3. Generar nombre único
	objectName := uuid.New().String() + ext
	contentType := file.Header.Get("Content-Type")

	src, err := file.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	// 4. Subir
	_, err = s.minioClient.PutObject(ctx, s.bucketName, objectName, src, file.Size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		return "", fmt.Errorf("error subiendo a Storage: %v", err)
	}

	// 5. Retornar URL absoluta
	fullURL := fmt.Sprintf("%s/%s/%s", s.publicURL, s.bucketName, objectName)
	return fullURL, nil
}