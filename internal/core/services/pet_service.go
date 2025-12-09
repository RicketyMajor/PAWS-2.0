package services

import (
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
)

type PetService struct{}

func NewPetService() *PetService {
	return &PetService{}
}

// Create guarda una nueva mascota en la BD
func (s *PetService) Create(name, petType, breed, description string, age int, lat, long float64, userID uint) (*domain.Pet, error) {
	newPet := domain.Pet{
		Name:        name,
		Type:        petType,
		Breed:       breed,
		Description: description,
		Age:         age,
		Latitude:    lat,
		Longitude:   long,
		Status:      domain.StatusAvailable,
		UserID:      userID, // Vinculamos la mascota al usuario logueado
	}

	if err := database.DB.Create(&newPet).Error; err != nil {
		return nil, err
	}

	return &newPet, nil
}

// GetAll devuelve todas las mascotas disponibles
func (s *PetService) GetAll() ([]domain.Pet, error) {
	var pets []domain.Pet
	// Preload("User") carga también los datos del dueño (JOIN)
	// Solo mostramos las disponibles
	err := database.DB.Preload("User").Where("status = ?", domain.StatusAvailable).Find(&pets).Error
	return pets, err
}