package domain

import (
	"time"
	"gorm.io/gorm"
)

// Review permite calificar una interacción finalizada
type Review struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	
	// Contexto
	MatchID   uint           `gorm:"index;not null" json:"match_id"`
	
	// Quién califica a quién
	AuthorID  uint           `gorm:"index;not null" json:"author_id"`
	TargetID  uint           `gorm:"index;not null" json:"target_id"`
	
	// Relaciones (para Preload)
	Author    User           `gorm:"foreignKey:AuthorID" json:"author,omitempty"`
	
	// Datos
	Rating    float64        `gorm:"not null" json:"rating"` // Float para medias estrellas (0.5, 1.5, etc)
	Comment   string         `gorm:"type:text" json:"comment"`

	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"` // Importante para saber cuándo se editó
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}