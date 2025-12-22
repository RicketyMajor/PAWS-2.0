package domain

import (
	"time"

	"gorm.io/gorm"
)

type MatchStatus string

const (
	MatchPending  MatchStatus = "pending"  // Like dado, esperando respuesta
	MatchAccepted MatchStatus = "accepted" // Rescatista aceptó -> Chat habilitado
	MatchRejected MatchStatus = "rejected" // Rescatista rechazó
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