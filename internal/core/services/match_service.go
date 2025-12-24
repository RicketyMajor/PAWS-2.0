package services

import (
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

type MatchService struct {
	db         *gorm.DB
	petService *PetService // Necesitamos acceder a datos de mascotas
}

// Actualizamos constructor para recibir DB
func NewMatchService(db *gorm.DB, petService *PetService) *MatchService {
	return &MatchService{
		db:         db,
		petService: petService,
	}
}

// GetSwipeDeck retorna las mascotas candidatas para un usuario específico
func (s *MatchService) GetSwipeDeck(userID uint) ([]domain.Pet, error) {
	// 1. Obtener Perfil del Usuario
	var profile domain.UserProfile
    err := s.db.Where("user_id = ?", userID).First(&profile).Error
    
    // CAMBIO: Si no hay perfil (usuario nuevo), retornamos TODAS las disponibles (excepto las ya vistas)
    // Esto asegura que el feed no esté vacío al principio.
    if err != nil {
        // Lógica simple: Traer todas las 'available' limitadas a 20
        var pets []domain.Pet
        // Aquí deberías agregar la lógica NOT IN (swipedPetIDs) si ya la tienes implementada
        result := s.db.Where("status = ?", domain.PetAvailable).Limit(20).Find(&pets)
        return pets, result.Error
    }

	// 2. Iniciar la Query base (Mascotas disponibles)
	query := s.db.Model(&domain.Pet{}).Where("status = ?", domain.PetAvailable)

	// 3. FILTRO DE EXCLUSIÓN: No mostrar mascotas con las que ya interactué
	// Subquery: SELECT pet_id FROM matches WHERE adopter_id = userID
	query = query.Where("id NOT IN (?)", 
		s.db.Model(&domain.Match{}).Select("pet_id").Where("adopter_id = ?", userID),
	)

	// 4. FILTROS INTELIGENTES (Hard Constraints)

	// A. Vivienda vs Patio
	if profile.Housing == domain.HousingApartment {
		// Si vive en depto, la mascota NO puede requerir patio
		query = query.Where("requires_yard = ?", false)
	}

	// B. Niños
	if profile.HasChildren {
		// Si tiene niños, la mascota DEBE ser buena con niños
		query = query.Where("good_with_kids = ?", true)
	}

	// C. Otras Mascotas (Simplificado)
	if profile.HasOtherPets {
		// Si tiene otras mascotas, debe ser sociable (asumimos perros por ahora)
		query = query.Where("good_with_dogs = ?", true)
	}

	// 5. Ejecutar y retornar
	var candidates []domain.Pet
	if err := query.Find(&candidates).Error; err != nil {
		return nil, err
	}

	return candidates, nil
}

// Swipe maneja la acción del Adoptante (Like/Dislike)
func (s *MatchService) Swipe(adopterID, petID uint, isLike bool) error {
	status := domain.MatchRejected
	if isLike {
		status = domain.MatchPending
	}

	// Buscamos si ya interactuó antes
	var existing domain.Match
	result := s.db.Where("adopter_id = ? AND pet_id = ?", adopterID, petID).First(&existing)

	if result.Error == nil {
		// Ya existe: Actualizamos su decisión (ej: se arrepintió)
		return s.db.Model(&existing).Update("status", status).Error
	}

	// No existe: Creamos el registro
	match := domain.Match{
		AdopterID: adopterID,
		PetID:     petID,
		Status:    domain.MatchStatus(status),
	}
	return s.db.Create(&match).Error
}

// GetPendingRequests obtiene las solicitudes para un Rescatista (Dueño de mascotas)
func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	
	// Join complejo: Matches -> Pet -> (Dueño = rescuerID)
	err := s.db.Preload("Adopter").Preload("Pet").
		Joins("JOIN pets ON pets.id = matches.pet_id").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
		Find(&matches).Error

	return matches, err
}

// RespondMatch maneja la respuesta del Rescatista (Aceptar/Rechazar)
func (s *MatchService) RespondMatch(rescuerID, matchID uint, accept bool) error {
	// 1. Verificar que el Match corresponde a una mascota de este Rescatista
	// (Seguridad: evitar que alguien acepte matches ajenos)
	var match domain.Match
	err := s.db.Joins("JOIN pets ON pets.id = matches.pet_id").
		Where("matches.id = ? AND pets.user_id = ?", matchID, rescuerID).
		First(&match).Error

	if err != nil {
		return err // No encontrado o no es dueño
	}

	// 2. Actualizar estado
	newStatus := domain.MatchRejected
	if accept {
		newStatus = domain.MatchAccepted
	}

	return s.db.Model(&match).Update("status", newStatus).Error
}