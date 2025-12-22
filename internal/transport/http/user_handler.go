package http

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

type UserHandler struct {
	userService  *services.UserService
	matchService *services.MatchService
}

func NewUserHandler(userService *services.UserService, matchService *services.MatchService) *UserHandler {
	return &UserHandler{
		userService:  userService,
		matchService: matchService,
	}
}

// UpdateProfile (PUT /profile)
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userID := c.MustGet("userID").(uint) // Del Token

	var req domain.UserProfile
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.userService.CreateOrUpdateProfile(userID, req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error actualizando perfil"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Perfil actualizado correctamente"})
}

// GetSwipeDeck (GET /matches/candidates) - El algoritmo en acción
func (h *UserHandler) GetSwipeDeck(c *gin.Context) {
	userID := c.MustGet("userID").(uint)

	pets, err := h.matchService.GetSwipeDeck(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error obteniendo candidatos o perfil incompleto"})
		return
	}

	c.JSON(http.StatusOK, pets)
}