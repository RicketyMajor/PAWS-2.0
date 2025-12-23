package services

import (
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

// 1. Agregar el campo db a la estructura
type PetService struct {
	db *gorm.DB 
}

// 2. Actualizar el constructor para pedir la DB
func NewPetService(db *gorm.DB) *PetService {
	return &PetService{
		db: db,
	}
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

// SearchNearby busca mascotas en un radio de 'distanceKM' desde (lat, lng)
func (s *PetService) SearchNearby(lat, lng float64, distanceKM float64) ([]domain.Pet, error) {
	var pets []domain.Pet

	// Fórmula de Haversine simplificada usando funciones de Postgres/PostGIS (si estuvieran activas)
	// O usando cálculo matemático directo en SQL estándar para compatibilidad.
	// Esta query calcula la distancia en Kilómetros.
	
	/* Explicación SQL:
       6371 = Radio de la tierra en KM.
       acos, cos, sin, radians = Funciones trigonométricas.
       Filtramos donde la distancia calculada sea menor al radio solicitado.
    */
	
	query := `
		SELECT *, (
			6371 * acos(
				cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + 
				sin(radians(?)) * sin(radians(latitude))
			)
		) AS distance 
		FROM pets 
		WHERE status = ? 
		HAVING distance < ? 
		ORDER BY distance ASC
	`

	// Nota: GORM raw query es necesaria aquí por la complejidad matemática
	err := s.db.Raw(query, lat, lng, lat, domain.PetAvailable, distanceKM).Scan(&pets).Error
	
	if err != nil {
		return nil, err
	}

	return pets, nil
}

// GetByID busca una mascota por su ID primario
func (s *PetService) GetByID(id uint) (*domain.Pet, error) {
	var pet domain.Pet
	// Usamos Preload para traer también los datos del usuario dueño si es necesario
	err := s.db.Preload("User").First(&pet, id).Error
	if err != nil {
		return nil, err
	}
	return &pet, nil
}