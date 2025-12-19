package http

import (
	"net/http"

	"github.com/gin-gonic/gin"
	
	// ELIMINAMOS "domain" PORQUE USAREMOS LOS STRUCTS LOCALES
	// "github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

// --- DTOs (Data Transfer Objects) LOCALES ---
// Es correcto definir esto aquí porque son exclusivos para recibir JSON

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type RegisterRequest struct {
	Name     string `json:"name" binding:"required"`
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
	Run      string `json:"run" binding:"required"`
	Role     string `json:"role" binding:"required,oneof=adopter rescuer"`
}

// --- HANDLER ---

type AuthHandler struct {
	service *services.AuthService
}

func NewAuthHandler(service *services.AuthService) *AuthHandler {
	return &AuthHandler{service: service}
}

// Register
func (h *AuthHandler) Register(c *gin.Context) {
    // CORRECCIÓN: Usamos 'RegisterRequest' local (sin 'domain.')
    var req RegisterRequest 

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Llamamos al servicio pasando los campos individuales
    err := h.service.Register(req.Email, req.Password, req.Name, req.Run, "adopter")
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusCreated, gin.H{"message": "Usuario creado exitosamente"})
}

// Login
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	token, err := h.service.Login(req.Email, req.Password)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token": token,
	})
}