// Package http contains the HTTP handlers for the application.
package http

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

// =========================================================================
// Handler Definition
// =========================================================================

// MatchHandler handles matching-related HTTP requests.
type MatchHandler struct {
	service *services.MatchService
}

// NewMatchHandler creates a new MatchHandler.
func NewMatchHandler(service *services.MatchService) *MatchHandler {
	return &MatchHandler{
		service: service,
	}
}

// =========================================================================
// Helper Functions
// =========================================================================

// getUserIDFromContext safely extracts the user ID from the Gin context.
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

// =========================================================================
// Handler Methods
// =========================================================================

// GetMatches handles the GET /matches/candidates request to fetch potential pet matches.
func (h *MatchHandler) GetMatches(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not identified"})
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error getting candidates: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, pets)
}

// Swipe handles the POST /matches/swipe request to record a user's swipe action.
func (h *MatchHandler) Swipe(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not identified"})
		return
	}

	var req struct {
		PetID  uint `json:"pet_id" binding:"required"`
		IsLike bool `json:"is_like"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON: " + err.Error()})
		return
	}

	if err := h.service.Swipe(userID, req.PetID, req.IsLike); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error processing swipe: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Action registered", "status": "success"})
}

// GetPending handles the GET /matches/requests request to fetch pending match requests.
func (h *MatchHandler) GetPending(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not identified"})
		return
	}

	matches, err := h.service.GetPendingRequests(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error getting requests"})
		return
	}

	c.JSON(http.StatusOK, matches)
}

// Respond handles the POST /matches/respond request to accept or reject a match.
func (h *MatchHandler) Respond(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not identified"})
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
		c.JSON(http.StatusForbidden, gin.H{"error": "You cannot respond to this match or it does not exist"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Response registered"})
}

// Unmatch handles the POST /matches/unmatch request to leave a chat/match.
func (h *MatchHandler) Unmatch(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok { c.JSON(http.StatusUnauthorized, gin.H{"error": "User not identified"}); return }
	
	var req struct { MatchID uint `json:"match_id" binding:"required"` }
	if err := c.ShouldBindJSON(&req); err != nil { c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()}); return }

	if err := h.service.Unmatch(userID, req.MatchID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error leaving chat: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "You have left the chat"})
}

// GetAdopterMatches handles GET /matches/adopter to get matches for the adopter role.
// It can filter by 'pending' or 'accepted' status.
func (h *MatchHandler) GetAdopterMatches(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not identified"})
		return
	}

	status := c.Query("status")

	if status == "pending" {
		matches, err := h.service.GetAdopterPendingMatches(userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error fetching pending matches"})
			return
		}
		c.JSON(http.StatusOK, matches)
	} else {
		matches, err := h.service.GetAcceptedMatches(userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error fetching accepted matches"})
			return
		}
		c.JSON(http.StatusOK, matches)
	}
}

// GetRescuerMatches handles GET /matches/rescuer to get matches for the rescuer role.
func (h *MatchHandler) GetRescuerMatches(c *gin.Context) {
	userID, ok := getUserIDFromContext(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not identified"})
		return
	}

	matches, err := h.service.GetRescuerMatches(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error fetching rescuer chats"})
		return
	}

	c.JSON(http.StatusOK, matches)
}