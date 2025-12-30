package domain

import "gorm.io/gorm"

type Report struct {
	gorm.Model
	
	// IDs (Llaves Foráneas)
	ReporterID uint   `gorm:"not null" json:"reporter_id"`
	ReportedID uint   `gorm:"not null" json:"reported_id"`

	// --- RELACIONES (Lo que te faltaba) ---
	// Esto le dice a GORM: "El campo Reporter es un User que se busca usando ReporterID"
	Reporter   User   `gorm:"foreignKey:ReporterID" json:"Reporter"`
	Reported   User   `gorm:"foreignKey:ReportedID" json:"Reported"`

	Reason     string `gorm:"not null" json:"reason"` 
	Status     string `gorm:"default:'pending'" json:"status"`
}