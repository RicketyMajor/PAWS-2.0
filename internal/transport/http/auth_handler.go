package http

import (
	"net/http"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services" // <--- CAMBIA ESTO
	"github.com/gin-gonic/gin"
)

// Estructura para recibir los datos del JSON (DTO)
type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}
type RegisterRequest struct {
	Name     string `json:"name" binding:"required"`
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
	Run      string `json:"run" binding:"required"`
	Role     string `json:"role" binding:"required,oneof=adopter rescuer"` // Solo permite estos dos valores
}

type AuthHandler struct {
	service *services.AuthService
}

func NewAuthHandler(service *services.AuthService) *AuthHandler {
	return &AuthHandler{service: service}
}

// Register es la función que Gin ejecutará cuando alguien llame a la API
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest

	// 1. Validar el JSON entrante
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 2. Llamar al servicio
	user, err := h.service.Register(req.Name, req.Email, req.Password, req.Run, req.Role)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}

	// 3. Responder con éxito
	c.JSON(http.StatusCreated, gin.H{
		"message": "Usuario registrado exitosamente",
		"user_id": user.ID,
	})
}
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	token, err := h.service.Login(req.Email, req.Password)
	if err != nil {
		// Retornamos 401 Unauthorized si falla el login
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token": token,
	})
}