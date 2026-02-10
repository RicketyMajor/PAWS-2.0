package http

import (
	"net/http"
	"strconv"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

type SocialHandler struct {
	chatService   *services.ChatService
	reviewService *services.ReviewService
}

func NewSocialHandler(chat *services.ChatService, review *services.ReviewService) *SocialHandler {
	return &SocialHandler{
		chatService:   chat,
		reviewService: review,
	}
}

// Helper interno para obtener ID seguro (puedes moverlo a un utils.go si prefieres)
func getUserIDSafe(c *gin.Context) (uint, bool) {
	idVal, exists := c.Get("userID")
	if !exists {
		return 0, false
	}
	switch v := idVal.(type) {
	case float64:
		return uint(v), true
	case uint:
		return v, true
	default:
		return 0, false
	}
}

// CreateReview (POST /reviews)
func (h *SocialHandler) CreateReview(c *gin.Context) {
	// Seguridad: Obtener ID del usuario autenticado
	idVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Auth required"})
		return
	}

	// Conversión segura de tipo
	var userID uint
	if v, ok := idVal.(float64); ok {
		userID = uint(v)
	} else {
		userID = idVal.(uint)
	}

	var req struct {
		MatchID uint    `json:"match_id" binding:"required"`
		Rating  float64 `json:"rating" binding:"required"` // Ahora es Float
		Comment string  `json:"comment"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Llamamos al servicio de Upsert
	if err := h.reviewService.CreateOrUpdateReview(req.MatchID, userID, req.Rating, req.Comment); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Calificación guardada exitosamente"})
}

// GetUserReviews (GET /users/:id/reviews) -> NUEVO
func (h *SocialHandler) GetUserReviews(c *gin.Context) {
	targetIDStr := c.Param("id")
	targetID, _ := strconv.Atoi(targetIDStr)

	reviews, err := h.reviewService.GetReviewsByTarget(uint(targetID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error cargando reseñas"})
		return
	}

	c.JSON(http.StatusOK, reviews)
}

// GetChatHistory (GET /matches/:id/messages)
func (h *SocialHandler) GetChatHistory(c *gin.Context) {
	matchIDStr := c.Param("id")
	matchID, _ := strconv.Atoi(matchIDStr)

	messages, err := h.chatService.GetHistory(uint(matchID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error cargando historial"})
		return
	}

	c.JSON(http.StatusOK, messages)
}

// --- NUEVO HANDLER: MARCAR COMO LEÍDO ---
func (h *SocialHandler) MarkAsRead(c *gin.Context) {
	userID, ok := getUserIDSafe(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

	matchIDStr := c.Param("id")
	matchID, err := strconv.Atoi(matchIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ID de match inválido"})
		return
	}

	if err := h.chatService.MarkAsRead(uint(matchID), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error marcando mensajes como leídos"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Mensajes marcados como leídos"})
}
