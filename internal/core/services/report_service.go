// Package services contains the core business logic of the application.
package services

import (
	"encoding/json"
	"errors"
	"time"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

// =========================================================================
// Service Definition
// =========================================================================

// ReportService provides business logic for user reporting and moderation.
type ReportService struct {
	db          *gorm.DB
	authService *AuthService
}

// NewReportService creates a new ReportService.
func NewReportService(db *gorm.DB, authService *AuthService) *ReportService {
	return &ReportService{
		db:          db,
		authService: authService,
	}
}

// =========================================================================
// Core Reporting Logic
// =========================================================================

// CreateReport allows a user to file a report against another user.
func (s *ReportService) CreateReport(reporterID, reportedID, matchID uint, category, description string) error {
	if reporterID == reportedID {
		return errors.New("you cannot report yourself")
	}

	report := domain.Report{
		ReporterID:  reporterID,
		ReportedID:  reportedID,
		MatchID:     matchID,
		Reason:      category,    // Legacy field to satisfy NOT NULL constraint
		Category:    category,    // New, preferred field
		Description: description,
		Status:      "pending",
	}

	// Save the new report.
	if err := s.db.Create(&report).Error; err != nil {
		return err
	}

	// --- Automatic Moderation Logic (Three Strikes Rule) ---
	var reportCount int64
	s.db.Model(&domain.Report{}).Where("reported_id = ?", reportedID).Count(&reportCount)

	if reportCount >= 3 {
		// 1. Mark the user as banned.
		s.db.Model(&domain.User{}).Where("id = ?", reportedID).Update("is_banned", true)

		// 2. Add the user to the global blacklist.
		var user domain.User
		if err := s.db.First(&user, reportedID).Error; err == nil {
			entry := domain.BlacklistEntry{
				Run:    user.Run,
				Name:   user.Name,
				Reason: "Automatic Ban: Multiple reports received.",
			}
			// Use FirstOrCreate to avoid duplicate entries.
			s.db.Where("run = ?", user.Run).FirstOrCreate(&entry)
		}
	}

	return nil
}

// GetReportDetails fetches a report and its associated chat history for the admin dashboard.
func (s *ReportService) GetReportDetails(reportID uint) (*domain.Report, []domain.Message, error) {
	var report domain.Report
	if err := s.db.Preload("Reporter").Preload("Reported").First(&report, reportID).Error; err != nil {
		return nil, nil, err
	}

	// Fetch chat history for context.
	var messages []domain.Message
	if report.MatchID != 0 {
		s.db.Where("match_id = ?", report.MatchID).Order("created_at asc").Find(&messages)
	}

	return &report, messages, nil
}

// GetAllPending retrieves all pending reports for the main admin dashboard.
func (s *ReportService) GetAllPending() ([]domain.Report, error) {
	var reports []domain.Report
	err := s.db.Preload("Reporter").Preload("Reported").
		Where("status = ?", "pending").
		Order("created_at desc").
		Find(&reports).Error
	return reports, err
}

// ResolveReport allows an admin to resolve a report by either banning the user or dismissing it.
func (s *ReportService) ResolveReport(adminID, reportID uint, action string, publicBlacklist bool) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var report domain.Report
		if err := tx.First(&report, reportID).Error; err != nil {
			return err
		}

		// 1. Take action based on admin's decision.
		if action == "ban" {
			// A. Ban the reported user.
			if err := tx.Model(&domain.User{}).Where("id = ?", report.ReportedID).Update("is_banned", true).Error; err != nil {
				return err
			}

			// B. Optionally add to the public blacklist.
			if publicBlacklist {
				var user domain.User
				tx.First(&user, report.ReportedID)

				entry := domain.BlacklistEntry{
					Run:    user.Run,
					Name:   user.Name,
					Reason: report.Category, // Use the report category as the public reason.
				}
				tx.Where("run = ?", user.Run).FirstOrCreate(&entry)
			}
		}

		// 2. Create an immutable snapshot of the chat evidence.
		if report.MatchID != 0 {
			var messages []domain.Message
			tx.Where("match_id = ?", report.MatchID).Order("created_at asc").Find(&messages)

			// Serialize to JSON to store as a frozen text record.
			evidenceJSON, _ := json.Marshal(messages)
			report.EvidenceSnapshot = string(evidenceJSON)
		}

		// 3. Close the report.
		now := time.Now()
		report.Status = "resolved"
		report.ResolverID = &adminID
		report.ResolvedAt = &now

		return tx.Save(&report).Error
	})
}

// =========================================================================
// Blacklist Logic
// =========================================================================

// SearchBlacklist looks up a RUN in the blacklist. The route requires a token; the
// reasoning lives at its registration in cmd/api/main.go.
func (s *ReportService) SearchBlacklist(rut string) (*domain.BlacklistEntry, error) {
	var entry domain.BlacklistEntry
	err := s.db.Where("run = ?", rut).First(&entry).Error
	return &entry, err
}
