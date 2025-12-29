package services

import (
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

type MatchService struct {
	db         *gorm.DB
	petService *PetService
}

func NewMatchService(db *gorm.DB, petService *PetService) *MatchService {
	return &MatchService{
		db:         db,
		petService: petService,
	}
}

// GetSwipeDeck: VERSIÓN ROBUSTA
func (s *MatchService) GetSwipeDeck(userID uint) ([]domain.Pet, error) {
	var pets []domain.Pet

	// SQL Puro para evitar confusiones de GORM con los Joins.
	// "Selecciona mascotas disponibles que NO estén en la tabla matches para este usuario"
	query := `
		SELECT p.* FROM pets p
		LEFT JOIN matches m ON m.pet_id = p.id AND m.adopter_id = ?
		WHERE m.id IS NULL 
		AND p.status = ?
		AND p.deleted_at IS NULL
	`

	err := s.db.Raw(query, userID, domain.StatusAvailable).Scan(&pets).Error
	return pets, err
}

// Swipe: (Sin cambios, pero asegúrate de que esté así)
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

// GetAcceptedMatches: (Chats - Ya lo tenías)
func (s *MatchService) GetAcceptedMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet.User").
		Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchAccepted).
		Find(&matches).Error
	return matches, err
}

// --- NUEVO: GetAdopterPendingMatches (Tus Likes Pendientes) ---
func (s *MatchService) GetAdopterPendingMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	// Solo cargamos la Mascota, no necesitamos al usuario todavía (no hay chat)
	err := s.db.Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchPending).
		Find(&matches).Error
	return matches, err
}

// GetPendingRequests: (Rescatista - Ya lo tenías, mantenlo igual)
func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").
		Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
		Find(&matches).Error
	return matches, err
}

// RespondMatch: (Ya lo tenías)
func (s *MatchService) RespondMatch(rescuerID, matchID uint, accept bool) error {
	status := domain.MatchRejected
	if accept {
		status = domain.MatchAccepted
	}
	return s.db.Model(&domain.Match{}).Where("id = ?", matchID).Update("status", status).Error
}

// GetRescuerMatches: (Ya lo tenías)
func (s *MatchService) GetRescuerMatches(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").
		Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchAccepted).
		Find(&matches).Error
	return matches, err
}