package domain

import (
	"gorm.io/gorm"
)

// PetStatus define en qué estado se encuentra la adopción
type PetStatus string

const (
	StatusAvailable PetStatus = "available"
	StatusAdopted   PetStatus = "adopted"
	StatusPending   PetStatus = "pending"
)

type Pet struct {
	gorm.Model

	// Información Básica
	Name        string    `gorm:"not null" json:"name"`
	Type        string    `gorm:"not null" json:"type"` // Dog, Cat, etc.
	Breed       string    `json:"breed"`                // Raza
	Age         int       `json:"age"`                  // Edad en meses o años
	Description string    `json:"description"`
	Status      PetStatus `gorm:"default:'available'" json:"status"`

	// Geolocalización (Para el futuro mapa)
	// Guardaremos latitud y longitud como floats por ahora. 
	// En la fase de PostGIS lo migraremos a tipo Geometry si es necesario.
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`

	// Relación con el Dueño (Rescatista)
	// Foreign Key: UserID conecta esta mascota con la tabla users
	UserID uint `json:"user_id"` 
	User   User `json:"-" gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE;"` 
	// 'json:"-"' evita que al pedir una mascota, se traiga todo el objeto usuario anidado siempre.

	// Imágenes (URLs)
	// Por simplicidad, guardaremos la URL de la foto principal aquí.
	PhotoURL string `json:"photo_url"`
}