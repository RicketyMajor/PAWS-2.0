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
}

func NewFileService() *FileService {
	// Leemos la configuración del .env
	endpoint := os.Getenv("MINIO_ENDPOINT")
	accessKeyID := os.Getenv("MINIO_ACCESS_KEY")
	secretAccessKey := os.Getenv("MINIO_SECRET_KEY")
	bucketName := os.Getenv("MINIO_BUCKET")
	useSSL := os.Getenv("MINIO_USE_SSL") == "true"
	publicURL := os.Getenv("STORAGE_PUBLIC_URL")

	// 1. Inicializar cliente MinIO
	minioClient, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKeyID, secretAccessKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		log.Fatalln("Error fatal inicializando MinIO:", err)
	}

	// 2. Auto-setup: Crear bucket si no existe
	ctx := context.Background()
	exists, err := minioClient.BucketExists(ctx, bucketName)
	if err != nil {
		log.Println("⚠️ Advertencia chequeando bucket:", err)
	} else if !exists {
		err = minioClient.MakeBucket(ctx, bucketName, minio.MakeBucketOptions{})
		if err != nil {
			log.Println("⚠️ Error creando bucket:", err)
		} else {
			log.Printf("✅ Bucket '%s' creado exitosamente.\n", bucketName)
			
			// 3. Hacer el bucket PÚBLICO (Política de lectura)
			policy := fmt.Sprintf(`{"Version": "2012-10-17","Statement": [{"Action": ["s3:GetObject"],"Effect": "Allow","Principal": {"AWS": ["*"]},"Resource": ["arn:aws:s3:::%s/*"]}]}`, bucketName)
			err = minioClient.SetBucketPolicy(ctx, bucketName, policy)
			if err != nil {
				log.Println("⚠️ No se pudo establecer política pública:", err)
			}
		}
	} else {
		log.Printf("ℹ️ Conectado al bucket existente: '%s'\n", bucketName)
	}

	return &FileService{
		minioClient: minioClient,
		bucketName:  bucketName,
		publicURL:   publicURL,
	}
}

// SaveImage sube el archivo a MinIO/S3 y retorna la URL completa
func (s *FileService) SaveImage(ctx context.Context, file *multipart.FileHeader) (string, error) {
	// 1. Validar extensión
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		return "", fmt.Errorf("formato no permitido (solo JPG/PNG)")
	}

	// 2. Generar nombre único
	objectName := uuid.New().String() + ext
	contentType := file.Header.Get("Content-Type")

	// 3. Abrir stream del archivo
	src, err := file.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	// 4. Subir a MinIO
	_, err = s.minioClient.PutObject(ctx, s.bucketName, objectName, src, file.Size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		return "", fmt.Errorf("error subiendo a MinIO: %v", err)
	}

	// 5. Retornar URL absoluta
	fullURL := fmt.Sprintf("%s/%s/%s", s.publicURL, s.bucketName, objectName)
	return fullURL, nil
}