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

	// 2. Obtener el Match y la Mascota relacionada
	var match domain.Match
	// IMPORTANTE: Hacemos Preload("Pet") para poder acceder al UserID del dueño de la mascota (Rescatista)
	if err := s.db.Preload("Pet").First(&match, matchID).Error; err != nil {
		return nil, 0, errors.New("match no encontrado")
	}

	// Validar estado (Usamos la constante que definiste en match.go)
	if match.Status != domain.MatchAccepted {
		return nil, 0, errors.New("no puedes chatear en un match no aceptado")
	}

	// 3. Determinar quién es el destinatario (Routing Lógico)
	// Definimos los actores:
	adopterID := match.AdopterID
	rescuerID := match.Pet.UserID // El dueño de la mascota es el rescatista

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