package http

import (
	"github.com/gin-gonic/gin"
	"net/http"
)

type WSHandler struct {
	hub *Hub
}

// NewWSHandler ahora recibe el Hub ya inicializado
func NewWSHandler(hub *Hub) *WSHandler {
	return &WSHandler{hub: hub}
}

func (h *WSHandler) HandleConnections(c *gin.Context) {
	// 1. Obtener usuario autenticado (del middleware)
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	
	// Conversión segura (la que aprendimos hoy)
	var userID uint
	switch v := userIDVal.(type) {
	case float64:
		userID = uint(v)
	case uint:
		userID = v
	default:
		userID = 0 // Fallback
	}

	// 2. Iniciar la conexión WebSocket
	ServeWs(h.hub, c, userID)
}