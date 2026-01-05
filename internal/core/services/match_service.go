package services

import (
	"encoding/json"
	"fmt"
	"log"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"gorm.io/gorm"
)

// Estructura del evento de notificación
type NotificationEvent struct {
	UserID uint   `json:"user_id"`
	Title  string `json:"title"`
	Body   string `json:"body"`
	Type   string `json:"type"`
}

type MatchService struct {
	db         *gorm.DB
	petService *PetService
	mqClient   *messaging.RabbitMQClient
}

func NewMatchService(db *gorm.DB, petService *PetService, mq *messaging.RabbitMQClient) *MatchService {
	return &MatchService{
		db:         db,
		petService: petService,
		mqClient:   mq,
	}
}

// GetSwipeDeck devuelve las mascotas disponibles para el usuario
func (s *MatchService) GetSwipeDeck(userID uint, lat, lon float64) ([]domain.Pet, error) {
	var pets []domain.Pet
	
	// Construimos la query base
	query := s.db.Table("pets p").
		Select("p.*").
		Joins("LEFT JOIN matches m ON m.pet_id = p.id AND m.adopter_id = ?", userID).
		Where("m.id IS NULL").
		Where("p.status = ?", domain.StatusAvailable).
		Where("p.deleted_at IS NULL")

	// Ordenamiento por distancia o fecha
	if lat != 0 && lon != 0 {
		orderClause := "((? - p.latitude) * (? - p.latitude) + (? - p.longitude) * (? - p.longitude)) ASC"
		query = query.Order(gorm.Expr(orderClause, lat, lat, lon, lon))
	} else {
		query = query.Order("p.created_at DESC")
	}

	// --- CORRECCIÓN CLAVE: PRELOAD IMAGES ---
	// Usamos Preload para traer la tabla relacionada 'pet_images'
	err := query.Preload("Images").Preload("User").Find(&pets).Error
	
	return pets, err
}

// Swipe registra la acción de like/dislike
func (s *MatchService) Swipe(adopterID, petID uint, isLike bool) error {
	status := domain.MatchPending
	if !isLike {
		status = domain.MatchRejected
	}
	var match domain.Match
	err := s.db.Where("adopter_id = ? AND pet_id = ?", adopterID, petID).First(&match).Error
	if err == nil {
		match.Status = status
		return s.db.Save(&match).Error
	}
	newMatch := domain.Match{
		AdopterID: adopterID,
		PetID:     petID,
		Status:    status,
	}
	
	return s.db.Create(&newMatch).Error
}

// RespondMatch maneja la respuesta del rescatista
func (s *MatchService) RespondMatch(rescuerID, matchID uint, accept bool) error {
	status := domain.MatchRejected
	if accept {
		status = domain.MatchAccepted
	}
	
	if err := s.db.Model(&domain.Match{}).Where("id = ?", matchID).Update("status", status).Error; err != nil {
		return err
	}

	if accept && s.mqClient != nil {
		go func() {
			var match domain.Match
			if err := s.db.Preload("Pet").First(&match, matchID).Error; err == nil {
				event := NotificationEvent{
					UserID: match.AdopterID,
					Title:  "¡Match! 🐾",
					Body:   fmt.Sprintf("Han aceptado tu solicitud para adoptar a %s. ¡Inicia el chat ahora!", match.Pet.Name),
					Type:   "match",
				}
				body, _ := json.Marshal(event)
				
				err := s.mqClient.Publish("push_notifications", body)
				if err != nil {
					log.Printf("Error enviando notificación RabbitMQ: %v", err)
				} else {
					log.Printf("Notificación Match enviada para usuario %d", match.AdopterID)
				}
			}
		}()
	}

	return nil
}

// GetAcceptedMatches (Para Adoptante - Chats Activos)
func (s *MatchService) GetAcceptedMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet.User").
		Preload("Pet.Images"). // <--- CORRECCIÓN: Cargar imágenes en el objeto anidado Pet
		Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchAccepted).
		Find(&matches).Error
	return matches, err
}

// GetAdopterPendingMatches (Para Adoptante - Enviados)
func (s *MatchService) GetAdopterPendingMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet.Images"). // <--- CORRECCIÓN
		Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchPending).
		Find(&matches).Error
	return matches, err
}

// GetPendingRequests (Para Rescatista - Solicitudes Recibidas)
func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").
		Preload("Pet.Images"). // <--- CORRECCIÓN
		Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
		Find(&matches).Error
	return matches, err
}

// GetRescuerMatches (Para Rescatista - Chats Activos)
func (s *MatchService) GetRescuerMatches(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").
		Preload("Pet.Images"). // <--- CORRECCIÓN
		Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchAccepted).
		Find(&matches).Error
	return matches, err
}