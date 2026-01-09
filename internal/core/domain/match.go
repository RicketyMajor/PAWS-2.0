package domain

import (
	"time"
	"gorm.io/gorm"
)

type MatchStatus string

const (
	MatchPending     MatchStatus = "pending"
	MatchAccepted    MatchStatus = "accepted"
	MatchRejected    MatchStatus = "rejected"
	// --- NUEVOS ESTADOS ---
	MatchAdopterLeft MatchStatus = "adopter_left" // El adoptante abandonó
	MatchRescuerLeft MatchStatus = "rescuer_left" // El rescatista abandonó
	MatchPetDeleted  MatchStatus = "pet_deleted"  // La mascota fue eliminada
)

type Match struct {
	ID        uint        `gorm:"primaryKey" json:"id"`
	
	// Quién dio el Like (Adoptante)
	AdopterID uint        `gorm:"index;not null" json:"adopter_id"`
	Adopter   User        `gorm:"foreignKey:AdopterID" json:"adopter,omitempty"`

	// A quién dio Like (Mascota)
	PetID     uint        `gorm:"index;not null" json:"pet_id"`
	Pet       Pet         `gorm:"foreignKey:PetID" json:"pet,omitempty"`

	// Estado del Match
	Status    MatchStatus `gorm:"type:varchar(20);default:'pending'" json:"status"`
	
	// Mensaje opcional inicial ("Me encantó tu perro porque...")
	Message   string      `json:"message"`

	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}