// Package domain contains the core data models for the application.
// This file defines the Message model, which is part of the chat system.
package domain

import (
	"time"
	"gorm.io/gorm"
)

// Message represents a single message within a chat (match).
type Message struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	
	// Association with the Match, which acts as the "chat room".
	MatchID   uint           `gorm:"index;not null" json:"match_id"`
	Match     Match          `gorm:"foreignKey:MatchID" json:"-"` // Ignored in JSON to prevent cycles.

	// Sender of the message.
	SenderID  uint           `gorm:"index;not null" json:"sender_id"`
	
	// Content and status.
	Content   string         `gorm:"type:text;not null" json:"content"`
	IsRead    bool           `gorm:"default:false" json:"is_read"`

	// Timestamps.
	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}