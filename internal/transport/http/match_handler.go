package http

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

type MatchHandler struct {
	service *services.MatchService
}

func NewMatchHandler(service *services.MatchService) *MatchHandler {
	return &MatchHandler{
		service: service,
	}
}

// GetMatches maneja la petición GET /pets/match
// Devuelve la lista de candidatos (Deck) para deslizar
func (h *MatchHandler) GetMatches(c *gin.Context) {
	// 1. Obtener el ID del usuario desde el Token (puesto por el middleware)
	userIDVal, exists := c.Get("userID")
	if !exists {
		// Si por alguna razón falló el middleware
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}
	userID := userIDVal.(uint)

	// 2. Llamar al servicio (CORRECCIÓN: Usar GetSwipeDeck en vez de FindMatches)
	pets, err := h.service.GetSwipeDeck(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo candidatos para match"})
		return
	}

	// 3. Responder con JSON
	c.JSON(http.StatusOK, pets)
}

// Swipe (POST /matches/swipe)
func (h *MatchHandler) Swipe(c *gin.Context) {
	userID := c.MustGet("userID").(uint)

	var req struct {
		PetID  uint `json:"pet_id" binding:"required"`
		IsLike bool `json:"is_like"` // true = like, false = dislike
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.service.Swipe(userID, req.PetID, req.IsLike); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error procesando swipe"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Acción registrada"})
}

// GetPending (GET /matches/requests) - Para el Rescatista
func (h *MatchHandler) GetPending(c *gin.Context) {
	userID := c.MustGet("userID").(uint)

	matches, err := h.service.GetPendingRequests(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo solicitudes"})
		return
	}

	c.JSON(http.StatusOK, matches)
}

// Respond (POST /matches/respond) - Para el Rescatista
func (h *MatchHandler) Respond(c *gin.Context) {
	userID := c.MustGet("userID").(uint)

	var req struct {
		MatchID uint `json:"match_id" binding:"required"`
		Accept  bool `json:"accept"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.service.RespondMatch(userID, req.MatchID, req.Accept); err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "No puedes responder a este match o no existe"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Respuesta registrada"})
}