package services

import (
	"errors"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

type ReviewService struct {
	db *gorm.DB
}

func NewReviewService(db *gorm.DB) *ReviewService {
	return &ReviewService{db: db}
}

func (s *ReviewService) CreateReview(matchID, authorID uint, rating int, comment string) error {
	// 1. Validaciones
	if rating < 1 || rating > 5 {
		return errors.New("la calificación debe ser entre 1 y 5")
	}

	// 2. Obtener datos del Match para saber quién es el "Target"
	var match domain.Match
	if err := s.db.First(&match, matchID).Error; err != nil {
		return errors.New("match no válido")
	}

	// Determinar a quién estamos calificando
	targetID := match.AdopterID
	if authorID == match.AdopterID {
		// Si el autor es el adoptante, califica al dueño de la mascota (Rescatista)
		// Necesitamos buscar al dueño de la mascota
		var pet domain.Pet
		s.db.First(&pet, match.PetID)
		targetID = pet.UserID
	}
	// Si el autor NO es el adoptante, asumimos que es el rescatista calificando al adoptante (targetID ya asignado arriba)

	// 3. Guardar Review
	review := domain.Review{
		MatchID:  matchID,
		AuthorID: authorID,
		TargetID: targetID,
		Rating:   rating,
		Comment:  comment,
	}

	return s.db.Create(&review).Error
}