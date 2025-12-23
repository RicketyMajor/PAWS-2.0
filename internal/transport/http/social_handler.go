package http

import (
	"net/http"
	"strconv"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
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

// CreateReview (POST /reviews)
func (h *SocialHandler) CreateReview(c *gin.Context) {
	userID := c.MustGet("userID").(uint)

	var req struct {
		MatchID uint   `json:"match_id" binding:"required"`
		Rating  int    `json:"rating" binding:"required"`
		Comment string `json:"comment"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.reviewService.CreateReview(req.MatchID, userID, req.Rating, req.Comment); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Reseña guardada"})
}