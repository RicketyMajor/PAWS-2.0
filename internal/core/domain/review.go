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
	AuthorID  uint           `gorm:"index;not null" json:"author_id"` // <--- ESTE ES EL QUE FALTA
	TargetID  uint           `gorm:"index;not null" json:"target_id"` // <--- Y ESTE
	
	// Datos
	Rating    int            `gorm:"not null" json:"rating"`          // <--- Y ESTE
	Comment   string         `gorm:"type:text" json:"comment"`        // <--- Y ESTE

	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}