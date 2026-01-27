package services

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// Constantes locales mapeadas al dominio
const (
	MatchAdopterLeft = domain.MatchAdopterLeft
	MatchRescuerLeft = domain.MatchRescuerLeft
	MatchPetDeleted  = domain.MatchPetDeleted
	MatchCancelled   = domain.MatchCancelled
	MatchAccepted    = domain.MatchAccepted
)

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

// GetSwipeDeck devuelve las mascotas disponibles para un adoptante, aplicando filtros lógicos.
func (s *MatchService) GetSwipeDeck(userID uint, lat, lon float64) ([]domain.Pet, error) {
	// 1. Obtener el RUT del usuario actual (Adoptante) para el Filtro Espejo
	var currentUser domain.User
	if err := s.db.Select("run").First(&currentUser, userID).Error; err != nil {
		return nil, fmt.Errorf("error identificando usuario: %v", err)
	}

	var pets []domain.Pet
	
	// Construcción de la Query
	query := s.db.Table("pets p").
		Select("p.*").
		// JOIN 1 (Filtro Espejo): Unimos con la tabla de usuarios dueños (u)
		Joins("INNER JOIN users u ON p.user_id = u.id").
		// JOIN 2 (Historial): Unimos con matches (m) para ver si ya interactuó
		Joins("LEFT JOIN matches m ON m.pet_id = p.id AND m.adopter_id = ?", userID).
		// CONDICIONES:
		Where("m.id IS NULL").                         // Que no haya swipe previo
		Where("p.status = ?", domain.StatusAvailable). // Que la mascota esté disponible
		Where("p.deleted_at IS NULL").                 // Que no esté eliminada
		Where("u.run <> ?", currentUser.Run)           // FILTRO ESPEJO: El dueño no puede tener mi mismo RUT

	// Lógica de ordenamiento (Geolocalización o Cronológico)
	if lat != 0 && lon != 0 {
		// Fórmula Haversine simplificada para ordenar por distancia
		orderClause := "((? - p.latitude) * (? - p.latitude) + (? - p.longitude) * (? - p.longitude)) ASC"
		query = query.Order(clause.Expr{SQL: orderClause, Vars: []interface{}{lat, lat, lon, lon}})
	} else {
		query = query.Order("p.created_at DESC")
	}

	// Ejecutar y cargar relaciones necesarias para la UI (Foto y Dueño)
	err := query.Preload("Images").Preload("User").Find(&pets).Error
	return pets, err
}

// Unmatch gestiona la lógica de estados para salir del chat
func (s *MatchService) Unmatch(userID, matchID uint) error {
	var match domain.Match

	// Usamos Unscoped para cargar incluso si la mascota fue borrada (Soft Delete)
	if err := s.db.Preload("Pet", func(db *gorm.DB) *gorm.DB {
		return db.Unscoped()
	}).First(&match, matchID).Error; err != nil {
		return errors.New("match no encontrado")
	}

	// Si ya está cancelado definitivamente, no hacemos nada
	if match.Status == MatchCancelled {
		return nil
	}

	var newStatus domain.MatchStatus

	// Lógica de Máquina de Estados:
	if userID == match.AdopterID {
		// --- SOY EL ADOPTANTE ---
		if match.Status == MatchRescuerLeft || match.Status == MatchPetDeleted {
			newStatus = MatchCancelled
		} else {
			newStatus = MatchAdopterLeft
		}

	} else if userID == match.Pet.UserID {
		// --- SOY EL RESCATISTA ---
		if match.Status == MatchAdopterLeft || match.Status == MatchPetDeleted {
			newStatus = MatchCancelled
		} else {
			newStatus = MatchRescuerLeft
		}

	} else {
		return errors.New("no tienes permiso para salir de este chat")
	}

	// Aplicar cambio
	if match.Status != newStatus {
		if err := s.db.Model(&match).Update("status", newStatus).Error; err != nil {
			return err
		}
	}

	return nil
}

// GetAcceptedMatches (Para el ADOPTANTE)
func (s *MatchService) GetAcceptedMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	
	err := s.db.Preload("Pet.User").
		Preload("Pet.Images").
		Preload("Pet", func(db *gorm.DB) *gorm.DB {
			return db.Unscoped()
		}).
		Where("adopter_id = ? AND status IN (?, ?, ?)", 
			adopterID, MatchAccepted, MatchRescuerLeft, MatchPetDeleted).
		Order("updated_at DESC").
		Find(&matches).Error
	
	for i := range matches {
		if !matches[i].Pet.DeletedAt.Time.IsZero() {
			matches[i].Pet.Status = domain.PetStatus("deleted") 
		}
	}
	return matches, err
}

// GetRescuerMatches (Para el RESCATISTA)
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
		Where("pets.user_id = ? AND matches.status IN (?, ?, ?)", 
			rescuerID, MatchAccepted, MatchAdopterLeft, MatchPetDeleted).
		Order("matches.updated_at DESC").
		Find(&matches).Error
	
	for i := range matches {
		if !matches[i].Pet.DeletedAt.Time.IsZero() {
			matches[i].Pet.Status = domain.PetStatus("deleted")
		}
	}
	return matches, err
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
	if accept { status = MatchAccepted }
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

func (s *MatchService) GetAdopterPendingMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet.Images").Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchPending).
		Order("created_at DESC").
		Find(&matches).Error
	return matches, err
}

func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Select("matches.*"). 
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").Preload("Pet.Images").Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
		Order("matches.created_at DESC").
		Find(&matches).Error
	return matches, err
}