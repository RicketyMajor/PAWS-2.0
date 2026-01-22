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

// CreateOrUpdateReview gestiona la calificación y actualiza el promedio del usuario destino
func (s *ReviewService) CreateOrUpdateReview(matchID, authorID uint, rating float64, comment string) error {
	// 1. Validaciones (0.5 a 5.0)
	if rating < 0.5 || rating > 5.0 {
		return errors.New("la calificación debe ser entre 0.5 y 5.0")
	}

	return s.db.Transaction(func(tx *gorm.DB) error {
		// 2. Obtener datos del Match para identificar al Target
		var match domain.Match
		if err := tx.First(&match, matchID).Error; err != nil {
			return errors.New("match no válido")
		}

		targetID := match.AdopterID
		if authorID == match.AdopterID {
			// Si soy el adoptante, califico al dueño (rescatista)
			var pet domain.Pet
			tx.First(&pet, match.PetID)
			targetID = pet.UserID
		}

		// 3. UPSERT: Buscar si ya existe una review de este autor para este match
		var existingReview domain.Review
		err := tx.Where("match_id = ? AND author_id = ?", matchID, authorID).First(&existingReview).Error

		if err == nil {
			// A. ACTUALIZAR (Sobrescribir)
			existingReview.Rating = rating
			existingReview.Comment = comment
			if err := tx.Save(&existingReview).Error; err != nil {
				return err
			}
		} else {
			// B. CREAR NUEVA
			newReview := domain.Review{
				MatchID:  matchID,
				AuthorID: authorID,
				TargetID: targetID,
				Rating:   rating,
				Comment:  comment,
			}
			if err := tx.Create(&newReview).Error; err != nil {
				return err
			}
		}

		// 4. RECALCULAR REPUTACIÓN DEL TARGET
		// Esto optimiza la lectura: calculamos al escribir, no al leer.
		return s.updateUserReputation(tx, targetID)
	})
}

// updateUserReputation calcula el promedio y total de reviews y actualiza la tabla Users
func (s *ReviewService) updateUserReputation(tx *gorm.DB, userID uint) error {
	type Result struct {
		AvgRating float64
		Total     int
	}
	var res Result

	// SQL Agregado
	err := tx.Model(&domain.Review{}).
		Select("AVG(rating) as avg_rating, COUNT(*) as total").
		Where("target_id = ?", userID).
		Scan(&res).Error
	
	if err != nil {
		return err
	}

	// Actualizar User
	return tx.Model(&domain.User{}).
		Where("id = ?", userID).
		Updates(map[string]interface{}{
			"average_rating": res.AvgRating,
			"review_count":   res.Total,
		}).Error
}

// GetReviewsByTarget obtiene todas las reseñas recibidas por un usuario
func (s *ReviewService) GetReviewsByTarget(targetID uint) ([]domain.Review, error) {
	var reviews []domain.Review
	err := s.db.Preload("Author"). // Cargamos quién escribió la reseña
		Where("target_id = ?", targetID).
		Order("updated_at desc"). // Las más recientes (o editadas) primero
		Find(&reviews).Error
	return reviews, err
}