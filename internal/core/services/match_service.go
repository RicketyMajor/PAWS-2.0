package services

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"gorm.io/gorm"
)

// Constantes para estados de abandono de chat
const (
	MatchAdopterLeft = "adopter_left"
	MatchRescuerLeft = "rescuer_left"
	MatchPetDeleted  = "pet_deleted" // Aseguramos que esta constante exista o usamos string directo
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

// Unmatch permite a un usuario salir de un chat, bloqueándolo para ambos.
func (s *MatchService) Unmatch(userID, matchID uint) error {
	var match domain.Match

	// CORRECCIÓN CRÍTICA: Usamos Unscoped() aquí.
	// Si la mascota fue eliminada, aún necesitamos cargarla para verificar
	// que el usuario actual (Rescatista) es el dueño legítimo y permitirle salir del chat.
	if err := s.db.Preload("Pet", func(db *gorm.DB) *gorm.DB {
		return db.Unscoped()
	}).First(&match, matchID).Error; err != nil {
		return errors.New("match no encontrado")
	}

	// Validamos si se puede salir
	if match.Status != domain.MatchAccepted && 
	   match.Status != MatchAdopterLeft && 
	   match.Status != MatchRescuerLeft && 
	   match.Status != domain.MatchPetDeleted { // Permitimos salir incluso si la mascota se borró
		
		if match.Status == domain.MatchRejected {
			return errors.New("este chat ya está cerrado")
		}
	}

	var newStatus domain.MatchStatus

	// Determinamos quién está cancelando
	if userID == match.AdopterID {
		newStatus = domain.MatchAdopterLeft
	} else if userID == match.Pet.UserID { // El dueño de la mascota es el Rescatista
		newStatus = domain.MatchRescuerLeft
	} else {
		return errors.New("no tienes permiso para salir de este chat")
	}

	// Si ya estaba en ese estado, no hacemos nada
	if match.Status == newStatus {
		return nil
	}

	// Actualizamos el estado
	if err := s.db.Model(&match).Update("status", newStatus).Error; err != nil {
		return err
	}

	return nil
}

// GetSwipeDeck ...
func (s *MatchService) GetSwipeDeck(userID uint, lat, lon float64) ([]domain.Pet, error) {
	var pets []domain.Pet
	query := s.db.Table("pets p").
		Select("p.*").
		Joins("LEFT JOIN matches m ON m.pet_id = p.id AND m.adopter_id = ?", userID).
		Where("m.id IS NULL").
		Where("p.status = ?", domain.StatusAvailable).
		Where("p.deleted_at IS NULL")

	if lat != 0 && lon != 0 {
		orderClause := "((? - p.latitude) * (? - p.latitude) + (? - p.longitude) * (? - p.longitude)) ASC"
		query = query.Order(gorm.Expr(orderClause, lat, lat, lon, lon))
	} else {
		query = query.Order("p.created_at DESC")
	}

	err := query.Preload("Images").Preload("User").Find(&pets).Error
	return pets, err
}

func (s *MatchService) Swipe(adopterID, petID uint, isLike bool) error {
	status := domain.MatchPending
	if !isLike { status = domain.MatchRejected }
	var match domain.Match
	err := s.db.Where("adopter_id = ? AND pet_id = ?", adopterID, petID).First(&match).Error
	if err == nil {
		match.Status = status
		return s.db.Save(&match).Error
	}
	newMatch := domain.Match{AdopterID: adopterID, PetID: petID, Status: status}
	return s.db.Create(&newMatch).Error
}

func (s *MatchService) RespondMatch(rescuerID, matchID uint, accept bool) error {
	status := domain.MatchRejected
	if accept { status = domain.MatchAccepted }
	
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
				s.mqClient.Publish("push_notifications", body)
			}
		}()
	}
	return nil
}

// GetAcceptedMatches (Adoptante)
func (s *MatchService) GetAcceptedMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	
	err := s.db.Preload("Pet.User").
		Preload("Pet.Images").
		Preload("Pet", func(db *gorm.DB) *gorm.DB {
			return db.Unscoped()
		}).
		// CORRECCIÓN: Incluimos MatchPetDeleted para que el adoptante vea el aviso
		Where("adopter_id = ? AND (status = ? OR status = ? OR status = ?)", 
			adopterID, domain.MatchAccepted, MatchRescuerLeft, domain.MatchPetDeleted).
		Order("updated_at DESC").
		Find(&matches).Error
	
	for i := range matches {
		if !matches[i].Pet.DeletedAt.Time.IsZero() {
			matches[i].Pet.Status = domain.PetStatus("deleted") 
		}
	}
	return matches, err
}

// GetAdopterPendingMatches ...
func (s *MatchService) GetAdopterPendingMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet.Images").Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchPending).
		Order("created_at DESC").
		Find(&matches).Error
	return matches, err
}

// GetPendingRequests (Rescatista)
func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	// Select matches.* evita ambigüedad de IDs
	err := s.db.Table("matches").
		Select("matches.*"). 
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").Preload("Pet.Images").Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
		Order("matches.created_at DESC").
		Find(&matches).Error
	return matches, err
}

// GetRescuerMatches (Rescatista)
func (s *MatchService) GetRescuerMatches(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	
	err := s.db.Table("matches").
		Select("matches.*").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").
		Preload("Pet.Images").
		Preload("Pet", func(db *gorm.DB) *gorm.DB {
			return db.Unscoped()
		}).
		// CORRECCIÓN: Incluimos MatchPetDeleted si queremos que el rescatista también vea 
		// el historial de chats de mascotas que él mismo eliminó.
		Where("pets.user_id = ? AND (matches.status = ? OR matches.status = ? OR matches.status = ?)", 
			rescuerID, domain.MatchAccepted, MatchAdopterLeft, domain.MatchPetDeleted).
		Order("matches.updated_at DESC").
		Find(&matches).Error
	
	for i := range matches {
		if !matches[i].Pet.DeletedAt.Time.IsZero() {
			matches[i].Pet.Status = domain.PetStatus("deleted")
		}
	}
	return matches, err
}