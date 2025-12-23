package services

import (
	"errors"
	"strings"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

type ChatService struct {
	db *gorm.DB
}

func NewChatService(db *gorm.DB) *ChatService {
	return &ChatService{db: db}
}

// Lista negra básica (en producción esto vendría de una BD o API externa)
var forbiddenWords = []string{"estafa", "odio", "matar", "depósito", "transferencia inmediata"}

// SaveMessage valida contenido y guarda el mensaje
func (s *ChatService) SaveMessage(matchID, senderID uint, content string) (*domain.Message, error) {
	// 1. Filtro "Evil PAWS" (Moderación de Contenido)
	if s.containsForbiddenContent(content) {
		return nil, errors.New("mensaje bloqueado por contener términos prohibidos o sospechosos")
	}

	// 2. Verificar que el Match esté aceptado
	var match domain.Match
	if err := s.db.First(&match, matchID).Error; err != nil {
		return nil, errors.New("match no encontrado")
	}
	if match.Status != domain.MatchAccepted {
		return nil, errors.New("no puedes chatear en un match no aceptado")
	}

	// 3. Guardar
	msg := domain.Message{
		MatchID:  matchID,
		SenderID: senderID,
		Content:  content,
	}

	if err := s.db.Create(&msg).Error; err != nil {
		return nil, err
	}

	return &msg, nil
}

// GetHistory recupera la conversación previa
func (s *ChatService) GetHistory(matchID uint) ([]domain.Message, error) {
	var messages []domain.Message
	// Ordenados por antigüedad (los más viejos primero, típìco de chats)
	err := s.db.Where("match_id = ?", matchID).Order("created_at asc").Find(&messages).Error
	return messages, err
}

// containsForbiddenContent busca palabras clave
func (s *ChatService) containsForbiddenContent(text string) bool {
	lowerText := strings.ToLower(text)
	for _, word := range forbiddenWords {
		if strings.Contains(lowerText, word) {
			return true
		}
	}
	return false
}