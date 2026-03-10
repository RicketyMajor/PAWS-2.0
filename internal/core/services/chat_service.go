// Package services contains the core business logic of the application.
package services

import (
	"errors"
	"strings"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

// forbiddenWords is a basic list for content filtering.
var forbiddenWords = []string{"scam", "hate", "kill", "deposit", "immediate transfer"}

// =========================================================================
// Service Definition
// =========================================================================

// ChatService provides business logic for chat-related operations.
type ChatService struct {
	db *gorm.DB
}

// NewChatService creates a new ChatService.
func NewChatService(db *gorm.DB) *ChatService {
	return &ChatService{db: db}
}

// =========================================================================
// Service Methods
// =========================================================================

// SaveMessage validates, saves, and determines the recipient of a chat message.
func (s *ChatService) SaveMessage(matchID, senderID uint, content string) (*domain.Message, uint, error) {
	// 1. Filter message content for forbidden words.
	if s.containsForbiddenContent(content) {
		return nil, 0, errors.New("message blocked due to inappropriate content")
	}

	// 2. Retrieve the match to validate status and participants.
	var match domain.Match
	if err := s.db.First(&match, matchID).Error; err != nil {
		return nil, 0, errors.New("match not found")
	}

	// Retrieve the pet (even if soft-deleted) to reliably get the rescuer's ID.
	var pet domain.Pet
	if err := s.db.Unscoped().First(&pet, match.PetID).Error; err != nil {
		return nil, 0, errors.New("pet not found")
	}

	// Validate that the match is active.
	if match.Status != domain.MatchAccepted {
		return nil, 0, errors.New("chat is not enabled for a non-accepted match")
	}

	// 3. Determine the recipient (logical routing).
	adopterID := match.AdopterID
	rescuerID := pet.UserID
	var receiverID uint

	if senderID == adopterID {
		receiverID = rescuerID
	} else if senderID == rescuerID {
		receiverID = adopterID
	} else {
		return nil, 0, errors.New("sender does not belong to this match")
	}

	// 4. Save the message.
	msg := domain.Message{
		MatchID:  matchID,
		SenderID: senderID,
		Content:  content,
		IsRead:   false,
	}

	if err := s.db.Create(&msg).Error; err != nil {
		return nil, 0, err
	}

	return &msg, receiverID, nil
}

// GetHistory retrieves the conversation history for a given match.
func (s *ChatService) GetHistory(matchID uint) ([]domain.Message, error) {
	var messages []domain.Message
	err := s.db.Where("match_id = ?", matchID).Order("created_at asc").Find(&messages).Error
	return messages, err
}

// MarkAsRead marks all messages in a match as read for a specific user.
func (s *ChatService) MarkAsRead(matchID, userID uint) error {
	// Updates all messages in the match where the current user is NOT the sender.
	return s.db.Model(&domain.Message{}).
		Where("match_id = ? AND sender_id != ? AND is_read = ?", matchID, userID, false).
		Update("is_read", true).Error
}

// containsForbiddenContent checks if the message contains any blacklisted words.
func (s *ChatService) containsForbiddenContent(text string) bool {
	lowerText := strings.ToLower(text)
	for _, word := range forbiddenWords {
		if strings.Contains(lowerText, word) {
			return true
		}
	}
	return false
}
