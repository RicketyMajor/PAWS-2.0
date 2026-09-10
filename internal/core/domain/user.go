// Package domain contains the core data models for the application.
package domain

import (
	"gorm.io/gorm"
)

// User represents a user in the system, who can be an adopter or a rescuer.
type User struct {
	gorm.Model

	Name string `gorm:"not null" json:"name"`

	// Composite indexes with Role allow the same Email/RUN if the Role is different.
	Email string `gorm:"index:idx_email_role,unique;not null" json:"email"`
	Run   string `gorm:"index:idx_run_role,unique;not null" json:"run"`

	Password string `gorm:"not null" json:"-"` // Hidden in JSON responses.

	// Role is part of the composite unique key.
	Role string `gorm:"default:'adopter';index:idx_email_role,unique;index:idx_run_role,unique" json:"role"`
	
	IsVerified bool `gorm:"default:false" json:"is_verified"`
	IsBanned   bool `gorm:"default:false" json:"is_banned"`

	// --- Basic Profile Data ---
	PhotoURL string `json:"photo_url"`
	Bio      string `gorm:"type:text" json:"bio"`
	Phone    string `json:"phone"`

	// --- Reputation Data (Cached) ---
	// These fields are updated by the ReviewService to avoid costly calculations on read.
	AverageRating float64 `gorm:"default:0" json:"average_rating"`
	ReviewCount   int     `gorm:"default:0" json:"review_count"`

	// --- Adopter Profile Data: Housing ---
	HousingType      string `json:"housing_type"`
	HousingOwnership string `json:"housing_ownership"`
	HasYard          bool   `json:"has_yard"`
	HasFence         bool   `json:"has_fence"`

	// --- Adopter Profile Data: Lifestyle ---
	FamilyComposition string `json:"family_composition"`
	OtherPets         string `json:"other_pets"`
	TimeAvailability  string `json:"time_availability"`
	Experience        string `json:"experience"`
}