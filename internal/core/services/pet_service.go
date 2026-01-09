package services

import (
	"errors"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

type PetService struct {
	db *gorm.DB 
}

func NewPetService(db *gorm.DB) *PetService {
	return &PetService{db: db}
}

// Create actualizada (Mantenemos la versión con Input DTO que hicimos antes)
// Si no tienes este struct definido en tu archivo actual, asegúrate de mantener tu versión de Create
// o usar la que definimos en el paso anterior.
type CreatePetInput struct {
	Name        string
	Type        string
	Breed       string
	Age         int
	Description string
	Latitude    float64
	Longitude   float64
	Address     string
	UserID      uint
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

func (s *PetService) Create(input CreatePetInput) (*domain.Pet, error) {
    mainPhoto := ""
    if len(input.ImageURLs) > 0 {
        mainPhoto = input.ImageURLs[0]
    }

	newPet := domain.Pet{
		Name:          input.Name,
		Type:          input.Type,
		Breed:         input.Breed,
		Description:   input.Description,
		Age:           input.Age,
		Latitude:      input.Latitude,
		Longitude:     input.Longitude,
		Address:       input.Address,
		PhotoURL:      mainPhoto,
		Status:        domain.StatusAvailable,
		UserID:        input.UserID,
		IsVaccinated:  input.IsVaccinated,
		IsSterilized:  input.IsSterilized,
		IsDewormed:    input.IsDewormed,
		SpecialNeeds:  input.SpecialNeeds,
        RequiresYard:  input.RequiresYard,
        GoodWithKids:  input.GoodWithKids,
        GoodWithDogs:  input.GoodWithDogs,
        EnergyLevel:   input.EnergyLevel,
	}

	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&newPet).Error; err != nil {
			return err
		}
        if len(input.ImageURLs) > 0 {
            var images []domain.PetImage
            for i, url := range input.ImageURLs {
                images = append(images, domain.PetImage{
                    PetID:   newPet.ID,
                    URL:     url,
                    IsCover: (i == 0),
                })
            }
            if err := tx.Create(&images).Error; err != nil {
                return err
            }
        }
		return nil
	})

	if err != nil {
		return nil, err
	}

    // Preload al devolver la creada
	s.db.Preload("User").Preload("Images").First(&newPet, newPet.ID)
	return &newPet, nil
}

// GetAll devuelve todas las mascotas disponibles
func (s *PetService) GetAll() ([]domain.Pet, error) {
	var pets []domain.Pet
	// CORRECCIÓN: Agregamos .Preload("Images")
	err := s.db.Preload("User").Preload("Images").Where("status = ?", domain.StatusAvailable).Find(&pets).Error
	return pets, err
}

// SearchNearby busca mascotas en un radio
func (s *PetService) SearchNearby(lat, lng float64, distanceKM float64) ([]domain.Pet, error) {
	var pets []domain.Pet
	
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
	
	// Scan NO hace Preload automáticamente porque es SQL crudo
	err := s.db.Raw(query, lat, lng, lat, domain.PetAvailable).Scan(&pets).Error
	if err != nil {
		return nil, err
	}
	
	// CORRECCIÓN MANUAL: Cargar relaciones para cada resultado
	for i := range pets {
		s.db.Model(&pets[i]).Association("Images").Find(&pets[i].Images)
		s.db.Model(&pets[i]).Association("User").Find(&pets[i].User)
	}
	
	return pets, nil
}

func (s *PetService) GetByID(id uint) (*domain.Pet, error) {
	var pet domain.Pet
	// CORRECCIÓN: Agregamos .Preload("Images")
	err := s.db.Preload("User").Preload("Images").First(&pet, id).Error
	return &pet, err
}

func (s *PetService) Delete(id uint, ownerID uint) error {
	// 1. Verificar propiedad
	var pet domain.Pet
	if err := s.db.Where("id = ? AND user_id = ?", id, ownerID).First(&pet).Error; err != nil {
		return errors.New("mascota no encontrada o sin permiso")
	}

	return s.db.Transaction(func(tx *gorm.DB) error {
		// A. Rechazar solicitudes pendientes (Ya lo tenías, mantenlo)
		if err := tx.Model(&domain.Match{}).
			Where("pet_id = ? AND status = ?", id, domain.MatchPending).
			Update("status", domain.MatchRejected).Error; err != nil {
			return err
		}

		// B. NUEVO: Bloquear chats activos (Accepted -> PetDeleted)
		// Esto hará que el ChatService impida nuevos mensajes
		if err := tx.Model(&domain.Match{}).
			Where("pet_id = ? AND status = ?", id, domain.MatchAccepted).
			Update("status", domain.MatchPetDeleted).Error; err != nil {
			return err
		}

		// C. Eliminar la mascota (Soft Delete)
		if err := tx.Delete(&domain.Pet{}, id).Error; err != nil {
			return err
		}

		return nil
	})
}