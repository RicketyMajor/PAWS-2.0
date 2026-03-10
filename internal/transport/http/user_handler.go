// Package http contains the HTTP handlers for the application.
package http

import (
	"net/http"
	"strconv"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

// =========================================================================
// Handler Definition
// =========================================================================

// UserHandler handles user-related HTTP requests.
type UserHandler struct {
	userService  *services.UserService
	matchService *services.MatchService
}

// NewUserHandler creates a new UserHandler.
func NewUserHandler(userService *services.UserService, matchService *services.MatchService) *UserHandler {
	return &UserHandler{
		userService:  userService,
		matchService: matchService,
	}
}

// =========================================================================
// Request & Response Structures
// =========================================================================

// UpdateProfileRequest defines the structure for the user profile update request.
type UpdateProfileRequest struct {
	Name     string `json:"name"`
	Bio      string `json:"bio"`
	Phone    string `json:"phone"`
	PhotoURL string `json:"photo_url"`

	HousingType       string `json:"housing_type"`
	HousingOwnership  string `json:"housing_ownership"`
	HasYard           bool   `json:"has_yard"`
	HasFence          bool   `json:"has_fence"`
	FamilyComposition string `json:"family_composition"`
	OtherPets         string `json:"other_pets"`
	TimeAvailability  string `json:"time_availability"`
	Experience        string `json:"experience"`
}

// =========================================================================
// Handler Methods
// =========================================================================

// UpdateProfile handles the PUT /profile endpoint.
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	var userID uint
	if val, ok := userIDVal.(float64); ok {
		userID = uint(val)
	} else {
		userID = userIDVal.(uint)
	}

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Separate data for the User table
	userUpdates := map[string]interface{}{
		"name":      req.Name,
		"bio":       req.Bio,
		"phone":     req.Phone,
		"photo_url": req.PhotoURL,
	}

	// Separate data for the UserProfile table
	profileData := &domain.UserProfile{
		HousingType:       req.HousingType,
		HousingOwnership:  req.HousingOwnership,
		HasYard:           req.HasYard,
		HasFence:          req.HasFence,
		FamilyComposition: req.FamilyComposition,
		OtherPets:         req.OtherPets,
		TimeAvailability:  req.TimeAvailability,
		Experience:        req.Experience,
	}

	err := h.userService.UpdateFullProfile(userID, userUpdates, profileData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error updating profile: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Profile updated successfully"})
}

// GetProfile handles the GET /profile endpoint.
func (h *UserHandler) GetProfile(c *gin.Context) {
	userIDVal, _ := c.Get("userID")
	var userID uint
	if val, ok := userIDVal.(float64); ok {
		userID = uint(val)
	} else {
		userID = userIDVal.(uint)
	}

	user, err := h.userService.GetUser(userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	profile, _ := h.userService.GetUserProfile(userID)
	if profile == nil {
		profile = &domain.UserProfile{} // Return empty profile if not created
	}

	// Return a nested JSON response
	c.JSON(http.StatusOK, gin.H{
		"user":    user,
		"profile": profile,
	})
}

// GetUserByID handles the GET /users/:id endpoint.
func (h *UserHandler) GetUserByID(c *gin.Context) {
	idStr := c.Param("id")
	userID, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	user, err := h.userService.GetUser(uint(userID))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}
