package http

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

// (Las structs Request se mantienen igual)
type RegisterRequest struct {
	Name     string `json:"name" binding:"required"`
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
	Run      string `json:"run" binding:"required"`
	Role     string `json:"role"`
}

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type OTPRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type OTPVerifyRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code" binding:"required,len=6"`
}

type AuthHandler struct {
	service    *services.AuthService
	otpService *services.OTPService
}

func NewAuthHandler(s *services.AuthService, otp *services.OTPService) *AuthHandler {
	return &AuthHandler{service: s, otpService: otp}
}

// Register: AHORA SOLO INICIA EL PROCESO (Redis + RabbitMQ)
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 1. Guardar datos en Redis (Temporal)
	err := h.service.InitiateRegistration(req.Name, req.Email, req.Password, req.Run, req.Role)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 2. Enviar OTP (RabbitMQ)
	_, err = h.otpService.GenerateOTP(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error enviando código de verificación"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Datos validados. Se ha enviado un código a tu correo para finalizar el registro.",
	})
}

// VerifyOTP: VALIDA EL CÓDIGO Y CREA LA CUENTA (Commit)
func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req OTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 1. Verificar si el código es correcto (Redis OTP)
	valid := h.otpService.VerifyOTP(req.Email, req.Code)
	if !valid {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Código incorrecto o expirado"})
		return
	}

	// 2. Intentar completar registro (Redis Pending -> Postgres)
	user, err := h.service.CompleteRegistration(req.Email)
	
	// Si err != nil, significa que no había registro pendiente.
	// Podría ser un usuario que ya existe y está logueándose con OTP (futuro passwordless).
	if err != nil {
		// Intentamos generar token como si fuera usuario existente
		token, tokenErr := h.service.GenerateTokenForEmail(req.Email)
		if tokenErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Sesión de registro expirada. Regístrate nuevamente."})
			return
		}
		c.JSON(http.StatusOK, gin.H{"message": "Bienvenido de vuelta", "token": token})
		return
	}

	// 3. Si se creó el usuario nuevo, generamos su token
	token, _ := h.service.GenerateTokenForUser(user)

	c.JSON(http.StatusCreated, gin.H{
		"message": "¡Cuenta creada exitosamente! Bienvenido a PAWS.",
		"token":   token,
		"user":    user,
	})
}

// Login, RequestOTP se mantienen...
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
	c.JSON(http.StatusOK, gin.H{"token": token})
}

func (h *AuthHandler) RequestOTP(c *gin.Context) {
	var req OTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	_, err := h.otpService.GenerateOTP(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error sistema OTP"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Código enviado"})
}