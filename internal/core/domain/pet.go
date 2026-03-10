// Package domain contains the core data models for the application.
package domain

import (
	"gorm.io/gorm"
)

// PetStatus defines the possible statuses for a pet.
type PetStatus string

const (
	StatusAvailable PetStatus = "available"
	StatusAdopted   PetStatus = "adopted"
	StatusPending   PetStatus = "pending"
)

// PetImage represents a single image in a pet's gallery.
type PetImage struct {
	ID      uint   `gorm:"primaryKey" json:"id"`
	PetID   uint   `gorm:"index;not null" json:"pet_id"` // Foreign key to Pet
	URL     string `json:"url"`
	IsCover bool   `json:"is_cover"` // Indicates if this is the main photo
}

// Pet represents an animal available for adoption.
type Pet struct {
	ID uint `gorm:"primaryKey" json:"id"`

	// --- Basic Information ---
	Name        string `json:"name"`
	Type        string `json:"type"` // e.g., "dog", "cat"
	Breed       string `json:"breed"`
	Age         int    `json:"age"`
	Gender      string `json:"gender"` // e.g., "male", "female"
	Description string `json:"description"`

	// --- Photo Gallery ---
	PhotoURL string     `json:"photo_url"`                                                // Legacy field, keeps the main photo URL for compatibility.
	Images   []PetImage `json:"images" gorm:"foreignKey:PetID;constraint:OnDelete:CASCADE;"` // Full image gallery.

	// --- Geolocation ---
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Address   string  `json:"address"` // e.g., "Hope Shelter, Santiago"

	// --- Status ---
	Status PetStatus `json:"status" gorm:"default:'available'"`

	// --- Veterinary & Health Information ---
	IsVaccinated bool   `json:"is_vaccinated"`
	IsSterilized bool   `json:"is_sterilized"`
	IsDewormed   bool   `json:"is_dewormed"`
	SpecialNeeds string `json:"special_needs,omitempty"` // e.g., "Blind", "Diabetic", or empty

	// --- Matchmaking & Lifestyle Preferences ---
	RequiresYard bool   `json:"requires_yard"`
	GoodWithKids bool   `json:"good_with_kids"`
	GoodWithDogs bool   `json:"good_with_dogs"`
	GoodWithCats bool   `json:"good_with_cats"`
	EnergyLevel  string `json:"energy_level"` // e.g., "low", "medium", "high"

	// --- Associations ---
	UserID uint `json:"user_id"`
	User   User `json:"user,omitempty" gorm:"foreignKey:UserID"`

	// --- Timestamps ---
	CreatedAt int64          `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt int64          `json:"updated_at" gorm:"autoUpdateTime"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}
