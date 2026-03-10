// Package services contains the core business logic of the application.
package services

import (
	"errors"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

// =========================================================================
// Service Definition
// =========================================================================

// ReviewService provides business logic for user reviews and reputation management.
type ReviewService struct {
	db *gorm.DB
}

// NewReviewService creates a new ReviewService.
func NewReviewService(db *gorm.DB) *ReviewService {
	return &ReviewService{db: db}
}

// =========================================================================
// Service Methods
// =========================================================================

// CreateOrUpdateReview creates a new review or updates an existing one for a given match.
// It then triggers a recalculation of the target user's reputation.
func (s *ReviewService) CreateOrUpdateReview(matchID, authorID uint, rating float64, comment string) error {
	// 1. Validate rating.
	if rating < 0.5 || rating > 5.0 {
		return errors.New("rating must be between 0.5 and 5.0")
	}

	return s.db.Transaction(func(tx *gorm.DB) error {
		// 2. Get match data to identify the review target.
		var match domain.Match
		if err := tx.First(&match, matchID).Error; err != nil {
			return errors.New("invalid match")
		}

		var targetID uint
		if authorID == match.AdopterID {
			// If the author is the adopter, the target is the rescuer (pet owner).
			var pet domain.Pet
			tx.First(&pet, match.PetID)
			targetID = pet.UserID
		} else {
			// Otherwise, the target is the adopter.
			targetID = match.AdopterID
		}

		// 3. Upsert: Find if a review from this author for this match already exists.
		var existingReview domain.Review
		err := tx.Where("match_id = ? AND author_id = ?", matchID, authorID).First(&existingReview).Error

		if err == nil {
			// A. Update existing review.
			existingReview.Rating = rating
			existingReview.Comment = comment
			if err := tx.Save(&existingReview).Error; err != nil {
				return err
			}
		} else {
			// B. Create a new review.
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

		// 4. Recalculate the target user's reputation.
		// This is an optimization to avoid calculating on every read.
		return s.updateUserReputation(tx, targetID)
	})
}

// GetReviewsByTarget retrieves all reviews received by a specific user.
func (s *ReviewService) GetReviewsByTarget(targetID uint) ([]domain.Review, error) {
	var reviews []domain.Review
	err := s.db.Preload("Author"). // Preload the author's data for display.
		Where("target_id = ?", targetID).
		Order("updated_at desc"). // Show most recent first.
		Find(&reviews).Error
	return reviews, err
}

// =========================================================================
// Helper Functions
// =========================================================================

// updateUserReputation calculates the average rating and total reviews for a user and updates their profile.
func (s *ReviewService) updateUserReputation(tx *gorm.DB, userID uint) error {
	type Result struct {
		AvgRating float64
		Total     int
	}
	var res Result

	// Use SQL aggregation to calculate the average and count.
	err := tx.Model(&domain.Review{}).
		Select("AVG(rating) as avg_rating, COUNT(*) as total").
		Where("target_id = ?", userID).
		Scan(&res).Error
	
	if err != nil {
		return err
	}

	// Update the User table with the new reputation data.
	return tx.Model(&domain.User{}).
		Where("id = ?", userID).
		Updates(map[string]interface{}{
			"average_rating": res.AvgRating,
			"review_count":   res.Total,
		}).Error
}