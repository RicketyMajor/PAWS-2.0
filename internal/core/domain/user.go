package domain

import (
	"gorm.io/gorm"
)

// User representa a cualquier actor en el sistema.
type User struct {
	gorm.Model

	Name string `gorm:"not null" json:"name"`

	// CAMBIO: Indices compuestos con el Rol.
	// Esto permite tener el mismo Email/Run si el Rol es diferente.
	Email string `gorm:"index:idx_email_role,unique;not null" json:"email"`
	Run   string `gorm:"index:idx_run_role,unique;not null" json:"run"`

	Password string `gorm:"not null" json:"-"`

	// El Rol es parte de la clave única compuesta ahora.
	Role       string `gorm:"default:'adopter';index:idx_email_role,unique;index:idx_run_role,unique" json:"role"`
	
	IsVerified bool   `gorm:"default:false" json:"is_verified"`
	IsBanned   bool   `gorm:"default:false" json:"is_banned"`

	// Datos de Perfil Básicos
	PhotoURL string `json:"photo_url"`
	Bio      string `gorm:"type:text" json:"bio"`
	Phone    string `json:"phone"`

	// --- REPUTACIÓN (CACHÉ) ---
	AverageRating float64 `gorm:"default:0" json:"average_rating"`
	ReviewCount   int     `gorm:"default:0" json:"review_count"`

	// --- DATOS: VIVIENDA ---
	HousingType      string `json:"housing_type"`
	HousingOwnership string `json:"housing_ownership"`
	HasYard          bool   `json:"has_yard"`
	HasFence         bool   `json:"has_fence"`

	// --- DATOS: ESTILO DE VIDA ---
	FamilyComposition string `json:"family_composition"`
	OtherPets         string `json:"other_pets"`
	TimeAvailability  string `json:"time_availability"`
	Experience        string `json:"experience"`

	// Token de Firebase
	FCMToken string `json:"fcm_token"`
}