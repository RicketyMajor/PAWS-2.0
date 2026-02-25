package domain

import (
	"time"

	"gorm.io/gorm"
)

// UserProfile contiene la información sociodemográfica del usuario
// Relación 1-a-1 con User
type UserProfile struct {
	ID     uint `gorm:"primaryKey" json:"id"`
	UserID uint `gorm:"uniqueIndex;not null" json:"user_id"` // FK a User

	// Datos de Vivienda y Entorno
	HousingType      string `json:"housing_type"`      // House, Apartment, Parcel
	HousingOwnership string `json:"housing_ownership"` // Owned, Rented
	HasYard          bool   `json:"has_yard"`
	HasFence         bool   `json:"has_fence"`

	// Datos de Familia y Rutina
	FamilyComposition string `json:"family_composition"` // Single, Couple, Family w/Kids, Seniors
	OtherPets         string `json:"other_pets"`         // None, Dogs, Cats, Both
	TimeAvailability  string `json:"time_availability"`  // Low, Medium, High
	Experience        string `json:"experience"`         // Beginner, Intermediate, Expert

	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}
