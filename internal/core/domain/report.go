package domain

import (
	"time"

	"gorm.io/gorm"
)

// Categorías de Reporte
const (
	ReportReasonAbuse = "abuse" // Maltrato animal
	ReportReasonScam  = "scam"  // Estafa
	ReportReasonSpam  = "spam"  // Spam/Comercial
	ReportReasonHate  = "hate"  // Lenguaje ofensivo/Odio
	ReportReasonOther = "other" // Otro
)

type Report struct {
	gorm.Model

	// Quien acusa y quien es acusado
	ReporterID uint `gorm:"not null;index" json:"reporter_id"`
	ReportedID uint `gorm:"not null;index" json:"reported_id"`

	// Relaciones
	Reporter User `gorm:"foreignKey:ReporterID" json:"reporter"`
	Reported User `gorm:"foreignKey:ReportedID" json:"reported"`

	// Contexto del Reporte
	MatchID uint `gorm:"index" json:"match_id"` // El chat donde ocurrió (opcional)

	// Datos del Reporte
	Category    string `gorm:"column:reason;type:varchar(50);not null" json:"category"` // Enum: abuse, scam, etc.
	Description string `gorm:"type:text" json:"description"`                            // Texto libre del usuario

	// Estado y Resolución
	Status string `gorm:"default:'pending';index" json:"status"` // pending, resolved, dismissed

	// EVIDENCIA INMUTABLE
	// Aquí guardaremos el historial del chat en JSON cuando el admin dicte sentencia.
	// Si borran el chat después, esto queda como prueba legal.
	EvidenceSnapshot string `gorm:"type:text" json:"evidence_snapshot"`

	ResolvedAt *time.Time `json:"resolved_at"`
	ResolverID *uint      `json:"resolver_id"` // ID del Admin que cerró el caso
}
