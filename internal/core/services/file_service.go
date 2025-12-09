package services

import (
	"errors"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
)

type FileService struct {
	uploadPath string
}

func NewFileService() *FileService {
	// Definimos la carpeta de destino. 
	// "." significa la carpeta actual donde corre el main.go
	return &FileService{uploadPath: "./uploads"}
}

// SaveImage guarda un archivo, validando que sea imagen y generando nombre único
func (s *FileService) SaveImage(file *multipart.FileHeader) (string, error) {
	// 1. Validar extensión (Seguridad básica)
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		return "", errors.New("formato de archivo no permitido (solo JPG/PNG)")
	}

	// 2. Generar nombre único (UUID)
	// Ejemplo: "a0eebc99-9c0b... .jpg"
	newFileName := uuid.New().String() + ext
	
	// 3. Crear la ruta destino completa
	dst := filepath.Join(s.uploadPath, newFileName)

	// 4. Abrir el archivo origen
	src, err := file.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	// 5. Crear el archivo destino en el disco
	out, err := os.Create(dst)
	if err != nil {
		return "", err
	}
	defer out.Close()

	// 6. Copiar los datos (Stream)
	if _, err = io.Copy(out, src); err != nil {
		return "", err
	}

	// 7. Retornar la ruta relativa para guardarla en la BD
	// Retornamos "/uploads/nombre.jpg" para que el frontend sepa dónde buscarla
	return "/uploads/" + newFileName, nil
}