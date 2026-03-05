package http

import (
	"net/http"
	"strconv"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
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

// Estructura auxiliar para recibir TODOS los datos del JSON
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

// UpdateProfile (PUT /profile)
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
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

	// Separar datos de la tabla User
	userUpdates := map[string]interface{}{
		"name":      req.Name,
		"bio":       req.Bio,
		"phone":     req.Phone,
		"photo_url": req.PhotoURL,
	}

	// Separar datos de la tabla UserProfile
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error actualizando perfil: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Perfil actualizado correctamente"})
}

// GetProfile (GET /profile)
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
		c.JSON(http.StatusNotFound, gin.H{"error": "Usuario no encontrado"})
		return
	}

	profile, _ := h.userService.GetUserProfile(userID)
	if profile == nil {
		profile = &domain.UserProfile{} // Devolver vacío si no hay perfil creado
	}

	// Devolvemos un JSON anidado robusto
	c.JSON(http.StatusOK, gin.H{
		"user":    user,
		"profile": profile,
	})
}

// GetUserByID (GET /users/:id)
func (h *UserHandler) GetUserByID(c *gin.Context) {
	idStr := c.Param("id")
	userID, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ID de usuario inválido"})
		return
	}

	user, err := h.userService.GetUser(uint(userID))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Usuario no encontrado"})
		return
	}

	c.JSON(http.StatusOK, user)
}
