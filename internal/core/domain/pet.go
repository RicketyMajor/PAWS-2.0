package domain

import (
	"gorm.io/gorm"
)

// Definimos el tipo para status
type PetStatus string

const (
	StatusAvailable PetStatus = "available" 
	StatusAdopted   PetStatus = "adopted"
	PetAvailable    PetStatus = "available"
	PetAdopted      PetStatus = "adopted"
	PetPending      PetStatus = "pending"
)

type Pet struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	
	// Datos básicos
	Name        string    `json:"name"`
	Type        string    `json:"type"`   // dog, cat
	Breed       string    `json:"breed"`
	Age         int       `json:"age"`
	Gender      string    `json:"gender"` // male, female
	Description string    `json:"description"`
	
	// CORRECCIÓN 1: Campo para la URL de la foto (Faltaba)
	PhotoURL    string    `json:"photo_url"` 

	// Geolocalización
	Latitude    float64   `json:"latitude"`
	Longitude   float64   `json:"longitude"`
	
	// Estado
	Status      PetStatus `json:"status" gorm:"default:'available'"`

	// Matchmaking (Preferencias)
	RequiresYard    bool   `json:"requires_yard"`
	GoodWithKids    bool   `json:"good_with_kids"`
	GoodWithDogs    bool   `json:"good_with_dogs"`
	GoodWithCats    bool   `json:"good_with_cats"`
	EnergyLevel     string `json:"energy_level"` // low, medium, high

	// CORRECCIÓN 2: Relaciones (El error 'unsupported relations' era por esto)
	UserID      uint      `json:"user_id"`
	User        User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
	
	// Auditoría
	CreatedAt   int64          `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt   int64          `json:"updated_at" gorm:"autoUpdateTime"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}