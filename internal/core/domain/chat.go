package domain

import (
	"time"
	"gorm.io/gorm"
)

// Message representa un mensaje individual en el chat
type Message struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	
	// Relación con el Match (El "Room" del chat)
	MatchID   uint           `gorm:"index;not null" json:"match_id"`
	Match     Match          `gorm:"foreignKey:MatchID" json:"-"` // JSON ignore para evitar ciclos

	// Quién envía
	SenderID  uint           `gorm:"index;not null" json:"sender_id"`
	
	// Contenido
	Content   string         `gorm:"type:text;not null" json:"content"`
	IsRead    bool           `gorm:"default:false" json:"is_read"`

	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}