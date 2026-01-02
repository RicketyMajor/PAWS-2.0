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
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No se ha enviado ningún archivo con la key 'file'"})
		return
	}

	// Usamos c.Request.Context() para que MinIO sepa si el usuario canceló la petición
	url, err := h.service.SaveImage(c.Request.Context(), file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error subiendo imagen: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"url": url, 
	})
}