// Package domain contains the core data models for the application.
package domain

import "gorm.io/gorm"

// BlacklistEntry represents a user who is permanently banned from the system.
// This is typically based on their national ID (RUN).
type BlacklistEntry struct {
	gorm.Model
	Run    string `gorm:"uniqueIndex;not null" json:"run"`   // The user's unique national ID.
	Name   string `json:"name"`                              // The user's name at the time of banning (for reference).
	Reason string `json:"reason"`                            // The public reason for the ban (e.g., "Animal Abuse").
}