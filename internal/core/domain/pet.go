package domain

import (
	"time"

	"gorm.io/gorm"
)

// Definimos el tipo
type PetStatus string

// CONSTANTES (Combinamos nombres para que nada falle)
const (
	// Nombres que espera tu pet_service.go actual
	StatusAvailable PetStatus = "available" 
	StatusAdopted   PetStatus = "adopted"
	
	// Alias para el nuevo código (opcional, apuntan a lo mismo)
	PetAvailable    PetStatus = "available"
	PetAdopted      PetStatus = "adopted"
	PetPending      PetStatus = "pending"
)

type Pet struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	Name        string    `json:"name"`
	Type        string    `json:"type"`   // dog, cat
	
	// --- CAMPOS RECUPERADOS (Que faltaban) ---
	Breed       string    `json:"breed"`     // <--- Faltaba esto
	Latitude    float64   `json:"latitude"`  // <--- Faltaba esto
	Longitude   float64   `json:"longitude"` // <--- Faltaba esto
	// -----------------------------------------

	Gender      string    `json:"gender"` // male, female
	Age         int       `json:"age"`    
	
	Status      PetStatus `json:"status"` 
	Description string    `json:"description"`
	
	// --- CAMPOS NUEVOS (Matchmaking) ---
	RequiresYard    bool   `json:"requires_yard"`
	GoodWithKids    bool   `json:"good_with_kids"`
	GoodWithDogs    bool   `json:"good_with_dogs"`
	GoodWithCats    bool   `json:"good_with_cats"`
	EnergyLevel     string `json:"energy_level"`

	// Relaciones
	UserID    uint           `json:"user_id"`
	
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}