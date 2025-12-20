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
	authService *services.AuthService
	otpService  *services.OTPService
}

func NewAuthHandler(authService *services.AuthService, otpService *services.OTPService) *AuthHandler {
	return &AuthHandler{
		authService: authService,
		otpService:  otpService,
	}
}

// Register
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// CORRECCIÓN 1 y 2:
	// - Pasamos req.Role (5to argumento).
	// - Solo capturamos 'err' (porque el servicio ya no devuelve token, solo error).
	err := h.authService.Register(req.Email, req.Password, req.Name, req.Run, req.Role)
	
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// CORRECCIÓN 3:
	// Como no tenemos token, respondemos con un mensaje de éxito.
	// El usuario tendrá que hacer Login después para obtener el token.
	c.JSON(http.StatusCreated, gin.H{"message": "Usuario registrado exitosamente. Por favor inicia sesión."})
}

// Login
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// ANTES: h.service.Login(...)
	// AHORA: h.authService.Login(...)
	token, err := h.authService.Login(req.Email, req.Password) // <--- CORREGIDO
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Credenciales inválidas"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"token": token})
}

func (h *AuthHandler) RequestOTP(c *gin.Context) {
	var body struct {
		Email string `json:"email" binding:"required,email"`
	}

	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Generar y "Enviar"
	_, err := h.otpService.GenerateOTP(body.Email)
	if err != nil {
		// Ojo: En prod no daríamos detalles del error de Redis
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error generando código"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Código de verificación enviado a tu correo"})
}

func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var body struct {
		Email string `json:"email" binding:"required,email"`
		Code  string `json:"code" binding:"required,len=6"`
	}

	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	isValid := h.otpService.VerifyOTP(body.Email, body.Code)
	if !isValid {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Código inválido o expirado"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "¡Verificación exitosa!",
		"status": "verified",
	})
}