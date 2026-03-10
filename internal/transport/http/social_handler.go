// Package http contains the HTTP handlers for the application.
package http

import (
	"net/http"
	"strconv"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

// =========================================================================
// Handler Definition
// =========================================================================

// SocialHandler handles social-related HTTP requests like reviews and chat.
type SocialHandler struct {
	chatService   *services.ChatService
	reviewService *services.ReviewService
}

// NewSocialHandler creates a new SocialHandler.
func NewSocialHandler(chat *services.ChatService, review *services.ReviewService) *SocialHandler {
	return &SocialHandler{
		chatService:   chat,
		reviewService: review,
	}
}

// =========================================================================
// Helper Functions
// =========================================================================

// getUserIDSafe safely extracts the user ID from the Gin context.
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

// =========================================================================
// Handler Methods
// =========================================================================

// CreateReview handles the POST /reviews endpoint to create or update a user review.
func (h *SocialHandler) CreateReview(c *gin.Context) {
	userID, ok := getUserIDSafe(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	var req struct {
		MatchID uint    `json:"match_id" binding:"required"`
		Rating  float64 `json:"rating" binding:"required"`
		Comment string  `json:"comment"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Use the upsert service method
	if err := h.reviewService.CreateOrUpdateReview(req.MatchID, userID, req.Rating, req.Comment); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Review saved successfully"})
}

// GetUserReviews handles the GET /users/:id/reviews endpoint to fetch reviews for a user.
func (h *SocialHandler) GetUserReviews(c *gin.Context) {
	targetIDStr := c.Param("id")
	targetID, _ := strconv.Atoi(targetIDStr)

	reviews, err := h.reviewService.GetReviewsByTarget(uint(targetID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error loading reviews"})
		return
	}

	c.JSON(http.StatusOK, reviews)
}

// GetChatHistory handles the GET /matches/:id/messages endpoint to fetch chat history.
func (h *SocialHandler) GetChatHistory(c *gin.Context) {
	matchIDStr := c.Param("id")
	matchID, _ := strconv.Atoi(matchIDStr)

	messages, err := h.chatService.GetHistory(uint(matchID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error loading history"})
		return
	}

	c.JSON(http.StatusOK, messages)
}

// MarkAsRead handles marking chat messages as read.
func (h *SocialHandler) MarkAsRead(c *gin.Context) {
	userID, ok := getUserIDSafe(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not identified"})
		return
	}

	matchIDStr := c.Param("id")
	matchID, err := strconv.Atoi(matchIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid match ID"})
		return
	}

	if err := h.chatService.MarkAsRead(uint(matchID), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error marking messages as read"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Messages marked as read"})
}
