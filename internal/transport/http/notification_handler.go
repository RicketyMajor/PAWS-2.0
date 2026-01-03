package http

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

type NotificationHandler struct {
	userService *services.UserService
}

func NewNotificationHandler(u *services.UserService) *NotificationHandler {
	return &NotificationHandler{userService: u}
}

type TokenRequest struct {
	Token string `json:"token" binding:"required"`
}

func (h *NotificationHandler) UpdateToken(c *gin.Context) {
	// 1. Obtener ID del usuario autenticado (del JWT)
	userIDVal, _ := c.Get("userID")
	// Conversión segura
	var userID uint
	switch v := userIDVal.(type) {
	case float64: userID = uint(v)
	case uint: userID = v
	default: userID = 0
	}

	var req TokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Token requerido"})
		return
	}

	// 2. Guardar en BD
	err := h.userService.UpdateFCMToken(userID, req.Token)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error guardando token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Token FCM actualizado"})
}