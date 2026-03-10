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

// PetService provides business logic for pet-related operations.
type PetService struct {
	db *gorm.DB
}

// NewPetService creates a new PetService.
func NewPetService(db *gorm.DB) *PetService {
	return &PetService{db: db}
}

// =========================================================================
// Input Structures
// =========================================================================

// CreatePetInput defines the data required to create a new pet.
type CreatePetInput struct {
	Name         string
	Type         string
	Breed        string
	Age          int
	Description  string
	Latitude     float64
	Longitude    float64
	Address      string
	UserID       uint
	IsVaccinated bool
	IsSterilized bool
	IsDewormed   bool
	SpecialNeeds string
	RequiresYard bool
	GoodWithKids bool
	GoodWithDogs bool
	EnergyLevel  string
	ImageURLs    []string
}

// =========================================================================
// Service Methods
// =========================================================================

// Create creates a new pet and its associated images in the database.
func (s *PetService) Create(input CreatePetInput) (*domain.Pet, error) {
	mainPhoto := ""
	if len(input.ImageURLs) > 0 {
		mainPhoto = input.ImageURLs[0]
	}

	newPet := domain.Pet{
		Name:         input.Name,
		Type:         input.Type,
		Breed:        input.Breed,
		Description:  input.Description,
		Age:          input.Age,
		Latitude:     input.Latitude,
		Longitude:    input.Longitude,
		Address:      input.Address,
		UserID:       input.UserID,
		IsVaccinated: input.IsVaccinated,
		IsSterilized: input.IsSterilized,
		IsDewormed:   input.IsDewormed,
		SpecialNeeds: input.SpecialNeeds,
		RequiresYard: input.RequiresYard,
		GoodWithKids: input.GoodWithKids,
		GoodWithDogs: input.GoodWithDogs,
		EnergyLevel:  input.EnergyLevel,
		PhotoURL:     mainPhoto,
		Status:       domain.StatusAvailable,
	}

	if err := s.db.Create(&newPet).Error; err != nil {
		return nil, err
	}

	// Save associated images
	if len(input.ImageURLs) > 0 {
		var images []domain.PetImage
		for i, url := range input.ImageURLs {
			images = append(images, domain.PetImage{
				PetID:   newPet.ID,
				URL:     url,
				IsCover: (i == 0),
			})
		}
		s.db.Create(&images)
	}

	return &newPet, nil
}

// GetAll retrieves all available pets.
func (s *PetService) GetAll() ([]domain.Pet, error) {
	var pets []domain.Pet
	err := s.db.Where("status = ?", domain.StatusAvailable).Find(&pets).Error
	return pets, err
}

// GetByUserID retrieves all pets owned by a specific user.
func (s *PetService) GetByUserID(userID uint) ([]domain.Pet, error) {
	var pets []domain.Pet
	err := s.db.Preload("Images").
		Where("user_id = ? AND deleted_at IS NULL", userID).
		Order("created_at DESC").
		Find(&pets).Error
	return pets, err
}

// GetNearby retrieves available pets within a certain distance of a given location.
func (s *PetService) GetNearby(lat, lng, dist float64) ([]domain.Pet, error) {
	var pets []domain.Pet
	// Simple Haversine formula in SQL
	query := `
		SELECT *, (
			6371 * acos(
				cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + 
				sin(radians(?)) * sin(radians(latitude))
			)
		) AS distance 
		FROM pets 
		WHERE status = ? AND deleted_at IS NULL 
		ORDER BY distance ASC
	`

	err := s.db.Raw(query, lat, lng, lat, domain.StatusAvailable).Scan(&pets).Error
	if err != nil {
		return nil, err
	}

	// Eager load associations for the found pets.
	for i := range pets {
		_ = s.db.Model(&pets[i]).Association("Images").Find(&pets[i].Images)
		_ = s.db.Model(&pets[i]).Association("User").Find(&pets[i].User)
	}

	return pets, nil
}

// GetByID retrieves a single pet by its ID, preloading user and image data.
func (s *PetService) GetByID(id uint) (*domain.Pet, error) {
	var pet domain.Pet
	err := s.db.Preload("User").Preload("Images").First(&pet, id).Error
	return &pet, err
}

// Delete performs a soft delete on a pet and updates the status of related matches.
func (s *PetService) Delete(id uint, ownerID uint) error {
	// 1. Verify ownership.
	var pet domain.Pet
	if err := s.db.Where("id = ? AND user_id = ?", id, ownerID).First(&pet).Error; err != nil {
		return errors.New("pet not found or permission denied")
	}

	return s.db.Transaction(func(tx *gorm.DB) error {
		// A. Reject all PENDING match requests for this pet.
		if err := tx.Model(&domain.Match{}).
			Where("pet_id = ? AND status = ?", id, domain.MatchPending).
			Update("status", domain.MatchRejected).Error; err != nil {
			return err
		}

		// B. Mark active chats (ACCEPTED matches) as 'PetDeleted'.
		if err := tx.Model(&domain.Match{}).
			Where("pet_id = ? AND status = ?", id, domain.MatchAccepted).
			Update("status", domain.MatchPetDeleted).Error; err != nil {
			return err
		}

		// C. Soft delete the pet itself.
		if err := tx.Delete(&domain.Pet{}, id).Error; err != nil {
			return err
		}

		return nil
	})
}
