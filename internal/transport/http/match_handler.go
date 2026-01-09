package http

import (
	"net/http"
	"strconv"

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

func getUserIDFromContext(c *gin.Context) (uint, bool) {
	idVal, exists := c.Get("userID")
	if !exists { return 0, false }
	switch v := idVal.(type) {
	case float64: return uint(v), true
	case uint: return v, true
	case int: return uint(v), true
	case uint64: return uint(v), true
	default: return 0, false
	}
}

// GetMatches maneja la petición GET /matches/candidates?lat=...&lon=...
func (h *MatchHandler) GetMatches(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

	latStr := c.Query("lat")
	lonStr := c.Query("lon")
	
	var lat, lon float64
	if latStr != "" && lonStr != "" {
		lat, _ = strconv.ParseFloat(latStr, 64)
		lon, _ = strconv.ParseFloat(lonStr, 64)
	}

	pets, err := h.service.GetSwipeDeck(userID, lat, lon)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo candidatos: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, pets)
}

// Swipe (POST /matches/swipe)
func (h *MatchHandler) Swipe(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

	var req struct {
		PetID  uint `json:"pet_id" binding:"required"`
		IsLike bool `json:"is_like"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "JSON inválido: " + err.Error()})
		return
	}

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

// Unmatch (POST /matches/unmatch) -> NUEVO
func (h *MatchHandler) Unmatch(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok { c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"}); return }
	
	var req struct { MatchID uint `json:"match_id" binding:"required"` }
	if err := c.ShouldBindJSON(&req); err != nil { c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()}); return }

	if err := h.service.Unmatch(userID, req.MatchID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error saliendo del chat: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Has salido del chat"})
}

// GetAdopterMatches (GET /matches/adopter) -> NUEVO UNIFICADO
// Reemplaza a GetMyMatches y GetMyPending
func (h *MatchHandler) GetAdopterMatches(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

	status := c.Query("status")

	if status == "pending" {
		matches, err := h.service.GetAdopterPendingMatches(userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo pendientes"})
			return
		}
		c.JSON(http.StatusOK, matches)
	} else {
		matches, err := h.service.GetAcceptedMatches(userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo mis matches"})
			return
		}
		c.JSON(http.StatusOK, matches)
	}
}

// GetRescuerMatches (GET /matches/rescuer)
func (h *MatchHandler) GetRescuerMatches(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

	matches, err := h.service.GetRescuerMatches(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo chats"})
		return
	}

	c.JSON(http.StatusOK, matches)
}