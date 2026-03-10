// Package domain contains the core data models for the application.
package domain

import (
	"time"

	"gorm.io/gorm"
)

// MatchStatus defines the possible states of a match interaction.
type MatchStatus string

const (
	MatchPending  MatchStatus = "pending"  // Initial state after an adopter swipes right.
	MatchAccepted MatchStatus = "accepted" // Rescuer accepts the request, chat is enabled.
	MatchRejected MatchStatus = "rejected" // Rescuer rejects the request.

	// --- Unilateral abandonment states ---
	MatchAdopterLeft MatchStatus = "adopter_left" // Adopter leaves the chat.
	MatchRescuerLeft MatchStatus = "rescuer_left" // Rescuer leaves the chat.
	MatchPetDeleted  MatchStatus = "pet_deleted"  // Rescuer deletes the pet profile.

	// --- Terminal state ---
	MatchCancelled MatchStatus = "cancelled" // Both parties have left the chat.
)

// Match represents an interaction between an adopter and a pet.
type Match struct {
	ID uint `gorm:"primaryKey" json:"id"`

	// --- Associations ---
	AdopterID uint `gorm:"index;not null" json:"adopter_id"`
	Adopter   User `gorm:"foreignKey:AdopterID" json:"adopter,omitempty"`

	PetID uint `gorm:"index;not null" json:"pet_id"`
	Pet   Pet  `gorm:"foreignKey:PetID" json:"pet,omitempty"`

	// --- State ---
	Status  MatchStatus `gorm:"type:varchar(20);default:'pending'" json:"status"`
	Message string      `json:"message"` // Optional message from adopter during swipe.

	// --- Virtual Fields (for JSON response, not stored in DB) ---
	UnreadCount int `json:"unread_count" gorm:"-"`

	// --- Timestamps ---
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

