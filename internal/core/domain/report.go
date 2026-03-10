// Package domain contains the core data models for the application.
package domain

import (
	"time"

	"gorm.io/gorm"
)

// ReportCategory defines the possible categories for a user report.
const (
	ReportReasonAbuse = "abuse" // Animal abuse
	ReportReasonScam  = "scam"  // Scam or fraud
	ReportReasonSpam  = "spam"  // Spam or commercial content
	ReportReasonHate  = "hate"  // Hate speech or offensive language
	ReportReasonOther = "other" // Other
)

// Report represents a report filed by one user against another.
type Report struct {
	gorm.Model

	// --- Participants ---
	ReporterID uint `gorm:"not null;index" json:"reporter_id"`
	ReportedID uint `gorm:"not null;index" json:"reported_id"`

	// --- Associations ---
	Reporter User `gorm:"foreignKey:ReporterID" json:"reporter"`
	Reported User `gorm:"foreignKey:ReportedID" json:"reported"`

	// --- Context ---
	MatchID uint `gorm:"index" json:"match_id"` // The chat where the incident occurred (optional).

	// --- Report Data ---
	Reason      string `gorm:"type:varchar(50);not null" json:"-"`        // Legacy field, hidden in JSON.
	Category    string `gorm:"type:varchar(50);not null" json:"category"` // The new, preferred field for the report category.
	Description string `gorm:"type:text" json:"description"`              // Free-text description from the user.

	// --- Resolution ---
	Status string `gorm:"default:'pending';index" json:"status"` // pending, resolved, dismissed

	// --- Immutable Evidence Snapshot ---
	// The chat history is serialized to JSON and stored here when an admin resolves the report.
	// This serves as a permanent record even if the original chat is deleted.
	EvidenceSnapshot string `gorm:"type:text" json:"evidence_snapshot,omitempty"`

	ResolvedAt *time.Time `json:"resolved_at,omitempty"`
	ResolverID *uint      `json:"resolver_id,omitempty"` // The ID of the admin who closed the case.
}
