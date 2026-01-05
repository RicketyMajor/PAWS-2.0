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

// --- NUEVA TABLA: IMÁGENES DE MASCOTA (Galería) ---
type PetImage struct {
	ID      uint   `gorm:"primaryKey" json:"id"`
	PetID   uint   `gorm:"index;not null" json:"pet_id"` // Clave foránea
	URL     string `json:"url"`
	IsCover bool   `json:"is_cover"` // Define si es la foto principal
}

type Pet struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	
	// Datos básicos
	Name        string    `json:"name"`
	Type        string    `json:"type"`   // dog, cat
	Breed       string    `json:"breed"`
	Age         int       `json:"age"`
	Gender      string    `json:"gender"` // male, female
	Description string    `json:"description"`
	
	// --- OBSOLETO (Mantenemos por compatibilidad temporal, pero usaremos Images) ---
	PhotoURL    string    `json:"photo_url"` 

	// --- NUEVA GALERÍA ---
	Images      []PetImage `json:"images" gorm:"foreignKey:PetID;constraint:OnDelete:CASCADE;"`

	// Geolocalización
	Latitude    float64   `json:"latitude"`
	Longitude   float64   `json: "longitude"`
	Address     string    `json:"address"` // Ej: "Refugio Esperanza, Santiago"

	// Estado
	Status      PetStatus `json:"status" gorm:"default:'available'"`

	// --- NUEVO: INFORMACIÓN VETERINARIA & SALUD ---
	IsVaccinated   bool   `json:"is_vaccinated"`
	IsSterilized   bool   `json:"is_sterilized"`
	IsDewormed     bool   `json:"is_dewormed"`
	SpecialNeeds   string `json:"special_needs"` // Ej: "Ciego", "Diabético", o vacío

	// Matchmaking (Preferencias / Estilo de Vida)
	RequiresYard    bool   `json:"requires_yard"`
	GoodWithKids    bool   `json:"good_with_kids"`
	GoodWithDogs    bool   `json:"good_with_dogs"`
	GoodWithCats    bool   `json:"good_with_cats"`
	EnergyLevel     string `json:"energy_level"` // low, medium, high

	// Relaciones
	UserID      uint      `json:"user_id"`
	User        User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
	
	// Auditoría
	CreatedAt   int64          `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt   int64          `json:"updated_at" gorm:"autoUpdateTime"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}