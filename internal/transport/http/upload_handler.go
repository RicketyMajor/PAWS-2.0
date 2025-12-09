package http

import (
	"net/http"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

type UploadHandler struct {
	service *services.FileService
}

func NewUploadHandler(service *services.FileService) *UploadHandler {
	return &UploadHandler{service: service}
}

func (h *UploadHandler) Upload(c *gin.Context) {
	// 1. Obtener el archivo del formulario (campo "file")
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "se requiere un archivo en el campo 'file'"})
		return
	}

	// 2. Llamar al servicio para guardar
	path, err := h.service.SaveImage(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// 3. Retornar la URL generada
	// El frontend usará esta URL para asignarla a una Mascota o Usuario
	c.JSON(http.StatusOK, gin.H{
		"url": path,
		"message": "imagen subida exitosamente",
	})
}