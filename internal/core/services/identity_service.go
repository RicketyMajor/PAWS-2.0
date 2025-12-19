package services

import (
	"context"
	"fmt"
	"mime/multipart"
	"path/filepath"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type IdentityService struct {
	minioClient *minio.Client
	bucketName  string
}

func NewIdentityService() *IdentityService {
	// ... (configuración del cliente igual que antes) ...
	endpoint := "minio-service:9000"
	accessKeyID := "minioadmin"
	secretAccessKey := "minioadmin"
	useSSL := false

	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKeyID, secretAccessKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		fmt.Println("Error conectando a MinIO:", err)
		return nil // O manejar mejor el error
	}

	// --- NUEVA LÓGICA DE AUTOMATIZACIÓN ---
	bucketName := "paws-identity"
	ctx := context.Background()
	
	// 1. Preguntamos si el bucket existe
	exists, errBucket := client.BucketExists(ctx, bucketName)
	if errBucket == nil && !exists {
		// 2. Si no existe, lo creamos automáticamente
		errCreate := client.MakeBucket(ctx, bucketName, minio.MakeBucketOptions{})
		if errCreate != nil {
			fmt.Println("Error creando bucket automático:", errCreate)
		} else {
			fmt.Println("Bucket 'paws-identity' creado automáticamente")
		}
	}
	// --------------------------------------

	return &IdentityService{
		minioClient: client,
		bucketName:  bucketName,
	}
}

// VerifyIdentity recibe la imagen, la guarda y (simula) extraer el RUT
func (s *IdentityService) VerifyIdentity(file *multipart.FileHeader) (string, error) {
	// 1. Abrir el archivo
	src, err := file.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	// 2. Generar nombre único para el archivo (ej: id_scan_12345.jpg)
	filename := fmt.Sprintf("id_scan_%s", filepath.Base(file.Filename))

	// 3. Subir a MinIO (Bucket Privado)
	ctx := context.Background()
	_, err = s.minioClient.PutObject(ctx, s.bucketName, filename, src, file.Size, minio.PutObjectOptions{
		ContentType: file.Header.Get("Content-Type"),
	})
	if err != nil {
		return "", fmt.Errorf("error subiendo documento: %v", err)
	}

	// 4. MOCK OCR: Aquí llamaríamos a Google Vision API o Tesseract.
	// Por ahora, simularemos que leímos el RUT exitosamente del nombre del archivo o devolvemos uno fijo.
	// Simulamos que el sistema leyó el RUT que querías probar.
	extractedRun := "11.111.111-1" 
	
	return extractedRun, nil
}