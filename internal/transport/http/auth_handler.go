package http

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

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
	otpService *services.OTPService // Ya inyectado en main.go
}

// Constructor (Ya lo tienes así en main.go, no cambiar)
func NewAuthHandler(s *services.AuthService, otp *services.OTPService) *AuthHandler {
	return &AuthHandler{service: s, otpService: otp}
}

// Register: Crea usuario Y envía OTP
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 1. Crear Usuario en BD
	user, err := h.service.Register(req.Name, req.Email, req.Password, req.Run, req.Role)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 2. ¡NUEVO! Generar y Enviar OTP Automáticamente
	// Esto dispara el evento a RabbitMQ -> Worker -> Email
	_, err = h.otpService.GenerateOTP(req.Email)
	if err != nil {
		// Si falla el OTP, no fallamos el registro, pero avisamos (o logueamos)
		// En un sistema estricto, podríamos hacer rollback, pero para MVP está bien.
		// El usuario siempre puede pedir "Reenviar código" después.
		c.JSON(http.StatusCreated, gin.H{
			"message": "Usuario registrado, pero hubo error enviando OTP. Intente reenviar.",
			"user_id": user.ID,
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Usuario registrado exitosamente. Código de verificación enviado.",
		"user_id": user.ID,
	})
}

// ... (Resto de funciones Login, RequestOTP, VerifyOTP se mantienen igual) ...

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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error generando OTP"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Código enviado"})
}

func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req OTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 1. Verificar el código en Redis
	valid := h.otpService.VerifyOTP(req.Email, req.Code)
	if !valid {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Código inválido o expirado"})
		return
	}

	// 2. CAMBIO: Generar Token JWT automáticamente (Auto-Login)
	token, err := h.service.GenerateTokenForEmail(req.Email)
	if err != nil {
		// Si el OTP es válido pero no encontramos al usuario en BD (raro, pero posible)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error generando sesión"})
		return
	}

	// 3. Devolver Token
	c.JSON(http.StatusOK, gin.H{
		"message": "Código verificado correctamente",
		"token":   token, // <--- ¡AQUÍ ESTÁ LA SOLUCIÓN!
	})
}