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

// Helper para obtener el UserID de forma segura sin causar Pánico
func getUserIDFromContext(c *gin.Context) (uint, bool) {
	idVal, exists := c.Get("userID")
	if !exists {
		return 0, false
	}

	// Manejo robusto de tipos:
	// JWT suele devolver float64, pero si cambiamos el middleware podría ser uint o int
	switch v := idVal.(type) {
	case float64:
		return uint(v), true
	case uint:
		return v, true
	case int:
		return uint(v), true
	case uint64:
		return uint(v), true
	default:
		return 0, false
	}
}

// GetMatches maneja la petición GET /pets/match
func (h *MatchHandler) GetMatches(c *gin.Context) {
	// 1. Obtener UserID seguro
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado o token inválido"})
		return
	}

	// 2. Llamar al servicio
	pets, err := h.service.GetSwipeDeck(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo candidatos para match: " + err.Error()})
		return
	}

	// 3. Responder con JSON
	c.JSON(http.StatusOK, pets)
}

// Swipe (POST /matches/swipe)
func (h *MatchHandler) Swipe(c *gin.Context) {
	// 1. Obtener UserID seguro
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

	var req struct {
		PetID  uint `json:"pet_id" binding:"required"`
		IsLike bool `json:"is_like"` // true = like, false = dislike
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "JSON inválido: " + err.Error()})
		return
	}

	// Nota: Si tu servicio Swipe devuelve (match, isMatch, error), ajusta esta línea.
	// Asumo que devuelve solo error según tu archivo original.
	if err := h.service.Swipe(userID, req.PetID, req.IsLike); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error procesando swipe: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Acción registrada", "status": "success"})
}

// GetPending (GET /matches/requests)
func (h *MatchHandler) GetPending(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

	matches, err := h.service.GetPendingRequests(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo solicitudes"})
		return
	}

	c.JSON(http.StatusOK, matches)
}

// Respond (POST /matches/respond)
func (h *MatchHandler) Respond(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

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