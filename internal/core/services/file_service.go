package services

import (
	"errors"
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
	return &FileService{uploadPath: "./uploads"}
}

// SaveImage guarda un archivo, validando que sea imagen y generando nombre único
func (s *FileService) SaveImage(file *multipart.FileHeader) (string, error) {
	// 1. Validar extensión
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		return "", errors.New("formato de archivo no permitido (solo JPG/PNG)")
	}

	// 2. CORRECCIÓN CRÍTICA: Asegurar que la carpeta existe
	// Si no existe, la crea con permisos de lectura/escritura (0755)
	if err := os.MkdirAll(s.uploadPath, 0755); err != nil {
		return "", errors.New("error creando directorio de uploads: " + err.Error())
	}

	// 3. Generar nombre único (UUID)
	newFileName := uuid.New().String() + ext
	
	// 4. Crear la ruta destino completa
	dst := filepath.Join(s.uploadPath, newFileName)

	// 5. Abrir el archivo origen
	src, err := file.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	// 6. Crear el archivo destino en el disco
	out, err := os.Create(dst)
	if err != nil {
		return "", err
	}
	defer out.Close()

	// 7. Copiar contenido (streaming)
	// Usamos io.Copy para ser eficientes con la memoria
	if _, err := out.ReadFrom(src); err != nil {
		return "", err
	}

	// 8. Retornar la ruta web relativa (para que el frontend la pueda usar)
	// Convertimos backslashes de Windows a slashes web "/"
	webPath := "/uploads/" + newFileName
	return webPath, nil
}