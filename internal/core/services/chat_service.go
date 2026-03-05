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

// Lista negra básica
var forbiddenWords = []string{"estafa", "odio", "matar", "depósito", "transferencia inmediata"}

// SaveMessage valida, guarda y RETORNA EL RECEIVER_ID
func (s *ChatService) SaveMessage(matchID, senderID uint, content string) (*domain.Message, uint, error) {
	// 1. Filtro de contenido
	if s.containsForbiddenContent(content) {
		return nil, 0, errors.New("mensaje bloqueado por contenido inapropiado")
	}

	// 2. Obtener el Match
	var match domain.Match
	if err := s.db.First(&match, matchID).Error; err != nil {
		return nil, 0, errors.New("match no encontrado")
	}

	// 2.1 Obtener la mascota explícitamente e incondicionalmente
	var pet domain.Pet
	if err := s.db.Unscoped().First(&pet, match.PetID).Error; err != nil {
		return nil, 0, errors.New("mascota no encontrada")
	}

	// Validar estado
	if match.Status != domain.MatchAccepted {
		return nil, 0, errors.New("no puedes chatear en un match no aceptado")
	}

	// 3. Determinar quién es el destinatario (Routing Lógico)
	adopterID := match.AdopterID
	rescuerID := pet.UserID // <-- AHORA ES 100% SEGURO

	var receiverID uint

	if senderID == adopterID {
		// Si escribe el adoptante, recibe el rescatista
		receiverID = rescuerID
	} else if senderID == rescuerID {
		// Si escribe el rescatista, recibe el adoptante
		receiverID = adopterID
	} else {
		return nil, 0, errors.New("no perteneces a este match")
	}

	// 4. Guardar mensaje
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

// GetHistory recupera la conversación previa
func (s *ChatService) GetHistory(matchID uint) ([]domain.Message, error) {
	var messages []domain.Message
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

// --- NUEVO MÉTODO: Marcar mensajes como leídos ---
func (s *ChatService) MarkAsRead(matchID, userID uint) error {
	// Actualiza todos los mensajes de ESTE match
	// donde el Sender NO sea el usuario actual ( userID != sender_id )
	// y que aún no estén leídos ( is_read = false )
	return s.db.Model(&domain.Message{}).
		Where("match_id = ? AND sender_id != ? AND is_read = ?", matchID, userID, false).
		Update("is_read", true).Error
}
