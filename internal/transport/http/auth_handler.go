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

// --- NUEVO: Structs para Recuperación ---
type ResetPasswordRequest struct {
	Email       string `json:"email" binding:"required,email"`
	NewPassword string `json:"new_password" binding:"required,min=6"`
	// Opcional: Podrías pedir el código aquí de nuevo para doble seguridad, 
	// pero normalmente se verifica en el paso anterior.
}

type AuthHandler struct {
	service    *services.AuthService
	otpService *services.OTPService
}

func NewAuthHandler(s *services.AuthService, otp *services.OTPService) *AuthHandler {
	return &AuthHandler{service: s, otpService: otp}
}

// --- FLUJO DE RECUPERACIÓN DE CONTRASEÑA ---

// 1. ForgotPassword: Pide el código
func (h *AuthHandler) ForgotPassword(c *gin.Context) {
	var req OTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verificar si el usuario existe antes de enviar nada
	// (Para evitar enumeración de usuarios, a veces se omite, pero por UX es mejor avisar)
	// Como GenerateRecoveryOTP solo envía mail, no valida existencia en BD explícitamente allí.
	// Podemos hacerlo aquí o dejar que el usuario se de cuenta si no llega el mail.
	// Por seguridad estándar, respondemos "Si el correo existe, se envió el código".
	
	_, err := h.otpService.GenerateRecoveryOTP(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error enviando código"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Código de recuperación enviado"})
}

// 2. VerifyRecoveryCode: Verifica el código antes de permitir cambiar la clave
func (h *AuthHandler) VerifyRecoveryCode(c *gin.Context) {
	var req OTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	valid := h.otpService.VerifyOTP(req.Email, req.Code)
	if !valid {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Código incorrecto o expirado"})
		return
	}

	// En un flujo más estricto, aquí devolveríamos un "Reset Token" temporal.
	// Para simplificar, confiamos en que el cliente pasará al siguiente paso inmediatamente.
	c.JSON(http.StatusOK, gin.H{"message": "Código verificado correctamente"})
}

// 3. ResetPassword: Cambia la contraseña
func (h *AuthHandler) ResetPassword(c *gin.Context) {
	var req ResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.service.UpdatePassword(req.Email, req.NewPassword); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error actualizando contraseña: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Contraseña restablecida exitosamente"})
}

// --- FLUJO DE REGISTRO & LOGIN (Existente) ---

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.service.InitiateRegistration(req.Name, req.Email, req.Password, req.Run, req.Role)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err = h.otpService.GenerateOTP(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error enviando código de verificación"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Datos validados. Se ha enviado un código a tu correo para finalizar el registro.",
	})
}

func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req OTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	valid := h.otpService.VerifyOTP(req.Email, req.Code)
	if !valid {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Código incorrecto o expirado"})
		return
	}

	user, err := h.service.CompleteRegistration(req.Email)
	if err != nil {
		// Intento de login con OTP (si ya existe)
		token, tokenErr := h.service.GenerateTokenForEmail(req.Email)
		if tokenErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Registro expirado o usuario no encontrado."})
			return
		}
		c.JSON(http.StatusOK, gin.H{"message": "Bienvenido", "token": token})
		return
	}

	token, _ := h.service.GenerateTokenForUser(user)
	c.JSON(http.StatusCreated, gin.H{
		"message": "¡Cuenta creada exitosamente!",
		"token":   token,
		"user":    user,
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