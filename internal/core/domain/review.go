// Package domain contains the core data models for the application.
package domain

import (
	"time"
	"gorm.io/gorm"
)

// Review allows a user to rate a completed interaction (match).
type Review struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	
	// --- Context ---
	MatchID   uint           `gorm:"index;not null" json:"match_id"`
	
	// --- Participants ---
	AuthorID  uint           `gorm:"index;not null" json:"author_id"` // The user writing the review.
	TargetID  uint           `gorm:"index;not null" json:"target_id"` // The user being reviewed.
	
	// --- Associations (for Preload) ---
	Author    User           `gorm:"foreignKey:AuthorID" json:"author,omitempty"`
	
	// --- Review Data ---
	Rating    float64        `gorm:"not null" json:"rating"` // Float to allow for half-star ratings.
	Comment   string         `gorm:"type:text" json:"comment"`

	// --- Timestamps ---
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"` // Important to know when a review was edited.
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}