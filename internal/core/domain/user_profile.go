// Package domain contains the core data models for the application.
package domain

import (
	"time"

	"gorm.io/gorm"
)

// UserProfile contains extended demographic information for a user,
// primarily used for the 'adopter' role. It has a one-to-one relationship with User.
type UserProfile struct {
	ID     uint `gorm:"primaryKey" json:"id"`
	UserID uint `gorm:"uniqueIndex;not null" json:"user_id"` // Foreign key to User

	// --- Housing & Environment ---
	HousingType      string `json:"housing_type"`      // e.g., House, Apartment, Parcel
	HousingOwnership string `json:"housing_ownership"` // e.g., Owned, Rented
	HasYard          bool   `json:"has_yard"`
	HasFence         bool   `json:"has_fence"`

	// --- Family & Lifestyle ---
	FamilyComposition string `json:"family_composition"` // e.g., Single, Couple, Family w/Kids, Seniors
	OtherPets         string `json:"other_pets"`         // e.g., None, Dogs, Cats, Both
	TimeAvailability  string `json:"time_availability"`  // e.g., Low, Medium, High
	Experience        string `json:"experience"`         // e.g., Beginner, Intermediate, Expert

	// --- Timestamps ---
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

