package domain

import "gorm.io/gorm"

// BlacklistEntry representa un usuario bloqueado del sistema [cite: 52]
type BlacklistEntry struct {
	gorm.Model
	Run    string `gorm:"uniqueIndex;not null"` // El RUN es único en la lista negra
	Reason string // Razón: "Maltrato", "Multicuenta", "Estafa"
}