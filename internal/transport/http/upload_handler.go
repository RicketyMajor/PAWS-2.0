package http

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

type UploadHandler struct {
	service *services.FileService
}

func NewUploadHandler(service *services.FileService) *UploadHandler {
	return &UploadHandler{service: service}
}

func (h *UploadHandler) Upload(c *gin.Context) {
	// 1. Recibir el archivo del form-data (key="file")
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No se ha enviado ningún archivo con la key 'file'"})
		return
	}

	// 2. Guardar usando el servicio
	// Esto devuelve algo como "/uploads/uuid-123.jpg"
	path, err := h.service.SaveImage(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error guardando imagen: " + err.Error()})
		return
	}

	// 3. Responder con la URL exacta que espera Flutter
	// Tu repositorio Dart busca: response.data['url']
	c.JSON(http.StatusOK, gin.H{
		"url": path, 
	})
}