package domain

import (
	"time"

	"gorm.io/gorm"
)

type HousingType string

const (
	HousingHouse     HousingType = "house"
	HousingApartment HousingType = "apartment"
	HousingParcel    HousingType = "parcel" // Parcela
)

// UserProfile contiene la información sociodemográfica del usuario
// Relación 1-a-1 con User
type UserProfile struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	UserID    uint           `gorm:"uniqueIndex;not null" json:"user_id"` // FK a User
	
	// Datos para el Algoritmo
	Housing   HousingType    `json:"housing"`             // Casa, Depto, Parcela
	HasYard   bool           `json:"has_yard"`            // ¿Tiene patio?
	HasChildren bool         `json:"has_children"`        // ¿Tiene niños?
	HasOtherPets bool        `json:"has_other_pets"`      // ¿Tiene otras mascotas?
	Experience   string      `json:"experience"`          // beginner, intermediate, expert
	TimeAvailable string     `json:"time_available"`      // low, medium, high (horas libres)

	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}