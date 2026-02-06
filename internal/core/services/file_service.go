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
	"github.com/cloudinary/cloudinary-go/v2/api" // <--- IMPORTANTE: Nuevo import
	"github.com/cloudinary/cloudinary-go/v2/api/uploader"
	"github.com/google/uuid"
)

type FileService struct {
	cld       *cloudinary.Cloudinary
	isEnabled bool
}

func NewFileService() *FileService {
	// 1. Configuración: Solo necesitamos la URL mágica de Cloudinary
	cldURL := os.Getenv("CLOUDINARY_URL")

	if cldURL == "" {
		log.Println("ADVERTENCIA: CLOUDINARY_URL no encontrada. Servicio de archivos desactivado (imágenes no se guardarán).")
		return &FileService{isEnabled: false}
	}

	// 2. Conexión
	cld, err := cloudinary.NewFromURL(cldURL)
	if err != nil {
		log.Printf("Error inicializando Cloudinary: %v. Servicio desactivado.\n", err)
		return &FileService{isEnabled: false}
	}

	log.Println("Servicio de almacenamiento (Cloudinary) conectado exitosamente.")

	return &FileService{
		cld:       cld,
		isEnabled: true,
	}
}

// SaveImage sube el archivo a Cloudinary y retorna la URL segura (HTTPS)
func (s *FileService) SaveImage(ctx context.Context, file *multipart.FileHeader) (string, error) {
	// Protección si el servicio falló al iniciar
	if !s.isEnabled {
		return "", fmt.Errorf("servicio de almacenamiento no disponible")
	}

	// Validación de extensión
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		return "", fmt.Errorf("formato inválido (solo JPG/PNG)")
	}

	// Abrir el archivo
	src, err := file.Open()
	if err != nil {
		return "", fmt.Errorf("error leyendo archivo: %v", err)
	}
	defer src.Close()

	// Generamos un ID único para el archivo en la nube
	uniqueFilename := uuid.New().String()

	// Subida a Cloudinary
	resp, err := s.cld.Upload.Upload(ctx, src, uploader.UploadParams{
		PublicID:     uniqueFilename,
		Folder:       "paws_uploads",
		ResourceType: "image",
		// CORRECCIÓN: Usamos api.Bool(true) en lugar de true directo
		Overwrite: api.Bool(true),
	})

	if err != nil {
		log.Printf("Error Cloudinary Upload: %v", err)
		return "", fmt.Errorf("error subiendo a la nube: %v", err)
	}

	// Retornamos la URL segura (https) que es permanente
	return resp.SecureURL, nil
}

// SaveMultipleImages reutiliza la lógica de SaveImage
func (s *FileService) SaveMultipleImages(ctx context.Context, files []*multipart.FileHeader) ([]string, error) {
	var urls []string

	if !s.isEnabled {
		return urls, fmt.Errorf("servicio no disponible")
	}

	for _, file := range files {
		url, err := s.SaveImage(ctx, file)
		if err != nil {
			log.Printf("Error subiendo una de las imágenes (%s): %v", file.Filename, err)
			return nil, err
		}
		urls = append(urls, url)
	}
	return urls, nil
}
