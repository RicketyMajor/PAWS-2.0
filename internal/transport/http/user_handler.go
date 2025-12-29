package http

import (
	"net/http"

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

// Estructura auxiliar para recibir los datos del JSON
type UpdateProfileRequest struct {
	Name     string `json:"name"`
	Bio      string `json:"bio"`
	Phone    string `json:"phone"`
	PhotoURL string `json:"photo_url"`
}

// UpdateProfile (PUT /profile)
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	// 1. Obtener ID del usuario
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
		return
	}
	// Manejo seguro de tipos (float64 -> uint)
	var userID uint
	if val, ok := userIDVal.(float64); ok {
		userID = uint(val)
	} else {
		userID = userIDVal.(uint)
	}

	// 2. Bind JSON
	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 3. Actualizar
	err := h.userService.UpdateIdentity(userID, req.Name, req.Bio, req.Phone, req.PhotoURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error actualizando perfil: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Perfil actualizado correctamente"})
}

// GetProfile (GET /profile) - Para cargar los datos actuales en el formulario
func (h *UserHandler) GetProfile(c *gin.Context) {
	userIDVal, _ := c.Get("userID")
	// Conversión segura de tipos
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

	c.JSON(http.StatusOK, user)
}

