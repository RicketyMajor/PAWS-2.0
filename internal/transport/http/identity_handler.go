package http

import (
	"net/http"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services" // <--- CAMBIA ESTO
	"github.com/gin-gonic/gin"
)

type VerificationRequest struct {
	DocumentImageURL string `json:"document_image_url" binding:"required"`
}

type IdentityHandler struct {
	service *services.IdentityService
}

func NewIdentityHandler(service *services.IdentityService) *IdentityHandler {
	return &IdentityHandler{service: service}
}

func (h *IdentityHandler) Verify(c *gin.Context) {
	// 1. Obtener ID del usuario del Token (Middleware)
	userIDFloat, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "no autorizado"})
		return
	}
	userID := uint(userIDFloat.(float64))

	// 2. Leer JSON (esperamos la URL de la foto que subió antes)
	var req VerificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 3. Llamar al servicio
	err := h.service.VerifyIdentity(userID, req.DocumentImageURL)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Identidad verificada exitosamente. Ahora tienes acceso total.",
		"status":  "verified",
	})
}