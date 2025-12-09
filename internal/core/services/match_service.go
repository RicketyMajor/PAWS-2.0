package services

import (
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain" // <--- Ajustar
)

type MatchService struct {
	petService *PetService
}

func NewMatchService(p *PetService) *MatchService {
	return &MatchService{petService: p}
}

// ScoredPet es una mascota con un puntaje de compatibilidad
type ScoredPet struct {
	Pet   domain.Pet `json:"pet"`
	Score int        `json:"match_score"` // 0 a 100
}

// FindMatches busca y puntúa mascotas según preferencias
func (s *MatchService) FindMatches(prefType, prefBreed string, prefMaxAge int, userLat, userLon float64) ([]ScoredPet, error) {
	// 1. Traemos TODAS las mascotas disponibles (Optimización: en un sistema real filtraríamos en SQL primero)
	// Usamos un mapa vacío para traer todo
	allPets, err := s.petService.Search(map[string]interface{}{}) 
	if err != nil {
		return nil, err
	}

	var matches []ScoredPet

	// 2. Algoritmo de Puntuación (En memoria)
	for _, pet := range allPets {
		score := 0

		// A. Compatibilidad de Tipo (Base crítica)
		if pet.Type == prefType {
			score += 40
		} else {
			// Si no es el tipo que quiere, el match es muy bajo, saltamos o penalizamos
			continue 
		}

		// B. Compatibilidad de Raza
		if prefBreed != "" && pet.Breed == prefBreed {
			score += 20
		}

		// C. Compatibilidad de Edad
		if prefMaxAge > 0 && pet.Age <= prefMaxAge {
			score += 20
		}

		// D. Proximidad (Bonus)
		// Aquí podríamos recalcular distancia exacta, por ahora simulamos lógica simple:
		// Si tiene coordenadas, damos puntos extra (asumiendo que el usuario quiere algo real)
		if pet.Latitude != 0 && pet.Longitude != 0 {
			score += 20
		}

		// Solo agregamos si hay un mínimo de interés
		if score > 0 {
			matches = append(matches, ScoredPet{Pet: pet, Score: score})
		}
	}

	// (Opcional) Aquí deberíamos ordenar `matches` por Score descendente.
	
	return matches, nil
}