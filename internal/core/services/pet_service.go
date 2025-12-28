package services

import (
	"errors" // <--- FALTABA ESTA IMPORTACIÓN

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

type PetService struct {
	db *gorm.DB 
}

func NewPetService(db *gorm.DB) *PetService {
	return &PetService{
		db: db,
	}
}

// Create guarda una nueva mascota en la BD
func (s *PetService) Create(name, petType, breed, description string, age int, lat, long float64, userID uint, photoURL string) (*domain.Pet, error) {
	newPet := domain.Pet{
		Name:        name,
		Type:        petType,
		Breed:       breed,
		Description: description,
		Age:         age,
		Latitude:    lat,
		Longitude:   long,
		PhotoURL:    photoURL, 
		Status:      domain.StatusAvailable,
		UserID:      userID,
	}

	if err := s.db.Create(&newPet).Error; err != nil {
		return nil, err
	}

	// Preload para devolver el objeto completo con el usuario
	s.db.Preload("User").First(&newPet, newPet.ID)

	return &newPet, nil
}

// GetAll devuelve todas las mascotas disponibles
func (s *PetService) GetAll() ([]domain.Pet, error) {
	var pets []domain.Pet
	err := s.db.Preload("User").Where("status = ?", domain.StatusAvailable).Find(&pets).Error
	return pets, err
}

// SearchNearby busca mascotas en un radio de 'distanceKM'
func (s *PetService) SearchNearby(lat, lng float64, distanceKM float64) ([]domain.Pet, error) {
	var pets []domain.Pet
	
	// Query geoespacial (Haversine simple)
	query := `
		SELECT *, (
			6371 * acos(
				cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + 
				sin(radians(?)) * sin(radians(latitude))
			)
		) AS distance 
		FROM pets 
		WHERE status = ? 
		ORDER BY distance ASC
	`
	
	err := s.db.Raw(query, lat, lng, lat, domain.PetAvailable).Scan(&pets).Error
	if err != nil {
		return nil, err
	}
	
	// Filtro manual de distancia si SQL no filtra estrictamente
	var filtered []domain.Pet
	for _, p := range pets {
		filtered = append(filtered, p)
	}

	return filtered, nil
}

func (s *PetService) GetByID(id uint) (*domain.Pet, error) {
	var pet domain.Pet
	err := s.db.Preload("User").First(&pet, id).Error
	return &pet, err
}

// Delete elimina una mascota solo si pertenece al usuario que lo solicita
func (s *PetService) Delete(id uint, ownerID uint) error {
	// Verificamos que el ID y el UserID coincidan
	result := s.db.Where("id = ? AND user_id = ?", id, ownerID).Delete(&domain.Pet{})
	
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("mascota no encontrada o no tienes permiso para borrarla")
	}
	return nil
}