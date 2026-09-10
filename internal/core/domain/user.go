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
	//
	// Email and Run are withheld from JSON by default, like Password. A User reaches a
	// response through four eager loads (a pet's owner, the swipe deck, a match, a
	// report), two of which serve unauthenticated routes, so anything serialized here
	// is public by default. The owner and an admin get them back explicitly through
	// SelfUser; nobody else has a use for them.
	Email string `gorm:"index:idx_email_role,unique;not null" json:"-"`
	Run   string `gorm:"index:idx_run_role,unique;not null" json:"-"`

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

// SelfUser renders a User for themselves or for an admin: the public projection plus
// the two identifiers the struct withholds. The outer fields shadow the embedded ones,
// which encoding/json resolves by depth, so the shape is the public one with `email`
// and `run` added back — not a second definition that can drift from it.
type SelfUser struct {
	User
	Email string `json:"email"`
	Run   string `json:"run"`
}

// NewSelfUser wraps u for a caller entitled to see the withheld identifiers.
func NewSelfUser(u User) SelfUser {
	return SelfUser{User: u, Email: u.Email, Run: u.Run}
}
