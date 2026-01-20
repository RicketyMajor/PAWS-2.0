package domain

import "gorm.io/gorm"

// BlacklistEntry representa un usuario bloqueado del sistema
type BlacklistEntry struct {
	gorm.Model
	Run    string `gorm:"uniqueIndex;not null" json:"run"` // RUT Único
	Name   string `json:"name"`                            // Nombre al momento del ban (referencia)
	Reason string `json:"reason"`                          // Razón pública (ej: "Maltrato Animal")
}