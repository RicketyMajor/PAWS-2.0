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
	
	// Estados de Abandono Unilateral
	MatchAdopterLeft MatchStatus = "adopter_left" // Adopter se fue, Rescuer lo ve
	MatchRescuerLeft MatchStatus = "rescuer_left" // Rescuer se fue, Adopter lo ve
	MatchPetDeleted  MatchStatus = "pet_deleted"  // Mascota borrada, ambos lo ven
	
	// Estado Terminal (Rompe el bucle)
	MatchCancelled   MatchStatus = "cancelled"    // Ambos se fueron, nadie lo ve
)

type Match struct {
	ID        uint        `gorm:"primaryKey" json:"id"`
	
	AdopterID uint        `gorm:"index;not null" json:"adopter_id"`
	Adopter   User        `gorm:"foreignKey:AdopterID" json:"adopter,omitempty"`

	PetID     uint        `gorm:"index;not null" json:"pet_id"`
	Pet       Pet         `gorm:"foreignKey:PetID" json:"pet,omitempty"`

	Status    MatchStatus `gorm:"type:varchar(20);default:'pending'" json:"status"`
	Message   string      `json:"message"`

	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}