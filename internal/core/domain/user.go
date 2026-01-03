package domain

import (

	"gorm.io/gorm"
)

// User representa a cualquier actor en el sistema.
type User struct {
	gorm.Model

	Name  string `gorm:"not null" json:"name"`
	Email string `gorm:"uniqueIndex;not null" json:"email"`
	Run   string `gorm:"uniqueIndex;not null" json:"run"`
	Password string `gorm:"not null" json:"-"`
	Role string `gorm:"default:'adopter'" json:"role"`
	IsVerified bool `gorm:"default:false" json:"is_verified"`
	IsBanned bool `gorm:"default:false" json:"is_banned"`

	// Datos de Perfil
	PhotoURL string `json:"photo_url"` 
	Bio      string `gorm:"type:text" json:"bio"`
	Phone    string `json:"phone"`

	// --- NUEVO CAMPO (Etapa 12) ---
	// Token de Firebase Cloud Messaging para Push Notifications
	FCMToken string `json:"fcm_token"` 
}
