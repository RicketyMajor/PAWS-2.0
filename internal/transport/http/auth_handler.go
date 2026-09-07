// Package http contains the HTTP handlers for the application.
package http

import (
	"errors"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

// =========================================================================
// Request & Response Structures
// =========================================================================

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

type ResetPasswordRequest struct {
	Email       string `json:"email" binding:"required,email"`
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

// =========================================================================
// Handler Definition
// =========================================================================

// AuthHandler handles authentication-related HTTP requests.
type AuthHandler struct {
	service    *services.AuthService
	otpService *services.OTPService
}

// NewAuthHandler creates a new AuthHandler.
func NewAuthHandler(s *services.AuthService, otp *services.OTPService) *AuthHandler {
	return &AuthHandler{service: s, otpService: otp}
}

// =========================================================================
// Role Switching
// =========================================================================

// SwitchRole handles the logic for a user to switch their active role.
func (h *AuthHandler) SwitchRole(c *gin.Context) {
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var userID uint
	if val, ok := userIDVal.(float64); ok {
		userID = uint(val)
	} else {
		userID = userIDVal.(uint)
	}

	newToken, newUser, err := h.service.SwitchRole(userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Role switched successfully",
		"token":   newToken,
		"user":    newUser,
	})
}

// =========================================================================
// Password Recovery
// =========================================================================

// ForgotPassword initiates the password recovery process by sending an OTP.
func (h *AuthHandler) ForgotPassword(c *gin.Context) {
	var req OTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.otpService.GenerateRecoveryOTP(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error sending recovery code"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Recovery code sent"})
}

// VerifyRecoveryCode verifies the password recovery OTP.
func (h *AuthHandler) VerifyRecoveryCode(c *gin.Context) {
	var req OTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	valid := h.otpService.VerifyOTP(req.Email, req.Code)
	if !valid {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired code"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Code verified successfully"})
}

// ResetPassword sets a new password after successful recovery verification.
func (h *AuthHandler) ResetPassword(c *gin.Context) {
	var req ResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.service.UpdatePassword(req.Email, req.NewPassword); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error updating password: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Password reset successfully"})
}

// =========================================================================
// Registration & Login
// =========================================================================

// Register initiates the user registration process.
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.service.InitiateRegistration(req.Name, req.Email, req.Password, req.Run, req.Role)
	if err != nil {
		// A dependency being down is not the caller's fault, and its message names hosts
		// and internal addresses. Report it as 503, log the cause, and tell the client
		// nothing about our infrastructure.
		if errors.Is(err, services.ErrUnavailable) {
			log.Printf("register: dependency unavailable: %v", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Service temporarily unavailable, please try again shortly"})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if _, err = h.otpService.GenerateOTP(req.Email); err != nil {
		// The mail provider's rejection reason exists only in this error. The client gets
		// a generic message, so without this line the cause is lost at every layer and a
		// failed signup is undiagnosable.
		log.Printf("register: sending verification code to %s failed: %v", req.Email, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error sending verification code"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Validation successful. A code has been sent to your email to complete registration.",
	})
}

// VerifyOTP verifies the registration OTP and completes the registration.
func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req OTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	valid := h.otpService.VerifyOTP(req.Email, req.Code)
	if !valid {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired code"})
		return
	}

	// Attempt to complete the registration
	user, err := h.service.CompleteRegistration(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error creating account: " + err.Error()})
		return
	}

	token, _ := h.service.GenerateTokenForUser(user)
	c.JSON(http.StatusCreated, gin.H{
		"message": "Account created successfully!",
		"token":   token,
		"user":    user,
	})
}

// Login handles user login and token generation.
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

// RequestOTP sends a new OTP for any registered email.
func (h *AuthHandler) RequestOTP(c *gin.Context) {
	var req OTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	_, err := h.otpService.GenerateOTP(req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "OTP system error"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Code sent"})
}
