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

// Search busca mascotas aplicando filtros dinámicos y cálculo de distancia
func (s *PetService) Search(filters map[string]interface{}) ([]domain.Pet, error) {
	var pets []domain.Pet
	
	// Iniciamos la consulta base
	query := database.DB.Model(&domain.Pet{}).Preload("User")

	// 1. Filtro por Estado (Siempre solo las disponibles)
	query = query.Where("status = ?", domain.StatusAvailable)

	// 2. Filtros de Texto (Tipo y Raza)
	if val, ok := filters["type"]; ok && val != "" {
		query = query.Where("type = ?", val)
	}
	if val, ok := filters["breed"]; ok && val != "" {
		// ILIKE es específico de Postgres para búsquedas insensibles a mayúsculas/minúsculas
		query = query.Where("breed ILIKE ?", "%"+val.(string)+"%")
	}
	if maxAge, ok := filters["max_age"].(int); ok && maxAge > 0 {
        query = query.Where("age <= ?", maxAge)
    }

	// 3. Filtro Geoespacial (La Magia)
	// Si nos dan coordenadas y radio, filtramos por distancia
	if lat, okLat := filters["lat"].(float64); okLat && lat != 0 {
		if long, okLong := filters["long"].(float64); okLong && long != 0 {
			if radius, okRadius := filters["radius"].(float64); okRadius && radius > 0 {
				// Fórmula SQL para calcular distancia en Kilómetros
				// (6371 es el radio de la Tierra en km)
				distanceFormula := "6371 * acos(cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + sin(radians(?)) * sin(radians(latitude)))"
				
				// Aplicamos la fórmula:
				// 1. Seleccionamos la distancia calculada (opcional, si quisiéramos mostrarla)
				// 2. Filtramos WHERE distancia < radius
				query = query.Where(distanceFormula+" < ?", lat, long, lat, radius)
			}
		}
	}

	// Ejecutar la consulta
	err := query.Find(&pets).Error
	return pets, err
}