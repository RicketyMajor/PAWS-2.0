package domain

import "gorm.io/gorm"

type Report struct {
	gorm.Model
	ReporterID uint   `gorm:"not null"` // Quién acusa
	ReportedID uint   `gorm:"not null"` // El acusado
	Reason     string `gorm:"not null"` // "Maltrato", "Acoso", "Cuenta Falsa"
	Status     string `gorm:"default:'pending'"` // pending, verified, rejected
}