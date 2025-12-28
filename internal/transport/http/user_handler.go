package http

import (
	"net/http"

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

// UpdateProfile maneja la actualización del perfil de usuario
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	// 1. Obtener ID del usuario del token (Forma segura float64 -> uint)
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
		return
	}
	userID := uint(userIDVal.(float64))

	// 2. Parsear el JSON del body
	var req domain.UserProfile
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 3. Llamar al servicio
	// Nota: Asignamos el ID del token al perfil para asegurar que se actualice el propio
	req.UserID = userID
	
	// CORRECCIÓN: Pasamos 'req' (valor) en lugar de '&req' (puntero)
	err := h.userService.CreateOrUpdateProfile(userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error actualizando perfil: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Perfil actualizado correctamente"})
}

// GetSwipeDeck obtiene las tarjetas de candidatos (Tinder-style)
func (h *UserHandler) GetSwipeDeck(c *gin.Context) {
	// 1. Obtener ID del usuario del token (Forma segura float64 -> uint)
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
		return
	}
	userID := uint(userIDVal.(float64))

	// 2. Obtener candidatos del servicio de Match
	pets, err := h.matchService.GetSwipeDeck(userID)
	if err != nil {
		// Si es un error de negocio, podríamos manejarlo, pero por ahora 500 está bien
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, pets)
}