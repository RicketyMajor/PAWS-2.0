package services

import (
	"context"
	"fmt"
	"math/rand" // Para generar números aleatorios
	"mime/multipart"
	"path/filepath"
	"strconv"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type IdentityService struct {
	minioClient *minio.Client
	bucketName  string
}

func NewIdentityService() *IdentityService {
	// ... (La configuración de conexión y MakeBucket se mantiene IGUAL) ...
    // Copia tu código de conexión existente aquí...
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
		return nil
	}

	bucketName := "paws-identity"
	ctx := context.Background()
	exists, errBucket := client.BucketExists(ctx, bucketName)
	if errBucket == nil && !exists {
		client.MakeBucket(ctx, bucketName, minio.MakeBucketOptions{})
	}

	return &IdentityService{
		minioClient: client,
		bucketName:  bucketName,
	}
}

// VerifyIdentity sube el archivo y retorna un RUN aleatorio simulado
func (s *IdentityService) VerifyIdentity(file *multipart.FileHeader) (string, error) {
	src, err := file.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	// Guardamos con timestamp para que no se sobrescriban los archivos
	filename := fmt.Sprintf("id_scan_%d_%s", time.Now().Unix(), filepath.Base(file.Filename))

	ctx := context.Background()
	_, err = s.minioClient.PutObject(ctx, s.bucketName, filename, src, file.Size, minio.PutObjectOptions{
		ContentType: file.Header.Get("Content-Type"),
	})
	if err != nil {
		return "", fmt.Errorf("error subiendo documento: %v", err)
	}

	// MOCK MEJORADO: Generar un RUT aleatorio válido para permitir múltiples registros
	mockRun := s.generateRandomRUN()
	
	return mockRun, nil
}

// generateRandomRUN crea un formato Chileno válido (ej: 12.345.678-K)
func (s *IdentityService) generateRandomRUN() string {
	// Semilla aleatoria
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	
	// Número entre 10.000.000 y 25.000.000
	number := r.Intn(15000000) + 10000000
	
	// Cálculo del Dígito Verificador (Algoritmo Módulo 11)
	dv := calculateDV(number)
	
	// Formatear con puntos
	return fmt.Sprintf("%s-%s", formatWithPoints(number), dv)
}

// Funciones auxiliares para el cálculo real del DV (Ingeniería de detalle)
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

func formatWithPoints(n int) string {
	s := strconv.Itoa(n)
	// Hack simple para poner puntos a un número de 8 dígitos (ej: 12.345.678)
	if len(s) == 8 {
		return fmt.Sprintf("%s.%s.%s", s[0:2], s[2:5], s[5:8])
	}
	return s // Fallback simple
}