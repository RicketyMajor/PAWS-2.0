package domain

import (
	"gorm.io/gorm"
)

// User representa a cualquier actor en el sistema.
type User struct {
	gorm.Model

	Name       string `gorm:"not null" json:"name"`
	Email      string `gorm:"uniqueIndex;not null" json:"email"`
	Run        string `gorm:"uniqueIndex;not null" json:"run"`
	Password   string `gorm:"not null" json:"-"`
	Role       string `gorm:"default:'adopter'" json:"role"`
	IsVerified bool   `gorm:"default:false" json:"is_verified"`
	IsBanned   bool   `gorm:"default:false" json:"is_banned"`

	// Datos de Perfil Básicos
	PhotoURL string `json:"photo_url"`
	Bio      string `gorm:"type:text" json:"bio"`
	Phone    string `json:"phone"`

	// --- NUEVOS DATOS: VIVIENDA (Para Evaluar Adopción) ---
	HousingType      string `json:"housing_type"`      // House, Apartment, Parcel
	HousingOwnership string `json:"housing_ownership"` // Owned, Rented
	HasYard          bool   `json:"has_yard"`          // ¿Tiene patio?
	HasFence         bool   `json:"has_fence"`         // ¿Tiene cerco seguro?

	// --- NUEVOS DATOS: ESTILO DE VIDA ---
	FamilyComposition string `json:"family_composition"` // Single, Couple, Kids, Seniors
	OtherPets         string `json:"other_pets"`         // None, Dogs, Cats, Both
	TimeAvailability  string `json:"time_availability"`  // Low (<2h), Medium (2-5h), High (>5h)
	Experience        string `json:"experience"`         // Beginner, Intermediate, Expert

	// Token de Firebase
	FCMToken string `json:"fcm_token"`
}