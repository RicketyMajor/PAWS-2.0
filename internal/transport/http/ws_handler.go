// Package http contains the HTTP handlers for the application.
package http

import (
	"github.com/gin-gonic/gin"
	"net/http"
)

// =========================================================================
// Handler Definition
// =========================================================================

// WSHandler handles the WebSocket connection upgrade.
type WSHandler struct {
	hub *Hub
}

// NewWSHandler creates a new WSHandler.
func NewWSHandler(hub *Hub) *WSHandler {
	return &WSHandler{hub: hub}
}

// =========================================================================
// Handler Methods
// =========================================================================

// HandleConnections upgrades the HTTP connection to a WebSocket connection.
func (h *WSHandler) HandleConnections(c *gin.Context) {
	// 1. Get the authenticated user ID from the context (set by middleware).
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	
	// 2. Safely cast the user ID to uint.
	var userID uint
	switch v := userIDVal.(type) {
	case float64:
		userID = uint(v)
	case uint:
		userID = v
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format in token"})
		return
	}

	// 3. Serve the WebSocket connection.
	ServeWs(h.hub, c, userID)
}