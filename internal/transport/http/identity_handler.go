package http

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

type IdentityHandler struct {
	service *services.IdentityService
}

func NewIdentityHandler(service *services.IdentityService) *IdentityHandler {
	return &IdentityHandler{service: service}
}

func (h *IdentityHandler) Verify(c *gin.Context) {
	// Recibir archivo del form-data (key: "document")
	file, err := c.FormFile("document")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Se requiere una imagen del documento"})
		return
	}

	// Llamar al servicio
	run, err := h.service.VerifyIdentity(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Retornar el RUN extraído (simulado) para que el frontend lo pre-llene
	c.JSON(http.StatusOK, gin.H{
		"message": "Documento verificado",
		"extracted_run": run,
		"status": "verified",
	})
}