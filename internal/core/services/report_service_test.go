// Package services_test contains unit tests for the services package.
package services

import (
	"testing"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

// TestThreeStrikesBan verifies the automatic banning logic after a user receives three reports.
func TestThreeStrikesBan(t *testing.T) {
	// 1. Arrange: Set up the database and services.
	db := setupTestDB() // Re-use the helper from auth_service_test.go
	if err := db.AutoMigrate(&domain.User{}, &domain.Report{}, &domain.BlacklistEntry{}); err != nil {
		t.Fatal("Failed to migrate test database:", err)
	}
	authService := NewAuthService(db)
	reportService := NewReportService(db, authService)

	// Create a "victim" user to be reported.
	victim := domain.User{Name: "Villain", Email: "bad@paws.cl", Run: "99.999.999-9"}
	db.Create(&victim)

	// 2. Act: Report the user twice.
	_ = reportService.CreateReport(2, victim.ID, 0, "user", "Harassment 1")
	_ = reportService.CreateReport(3, victim.ID, 0, "user", "Harassment 2")

	// 3. Assert: Check that the user is NOT yet banned.
	isBanned, _ := authService.CheckBlacklist(victim.Run)
	if isBanned {
		t.Error("User was banned after only 2 reports (prematurely).")
	}

	// 4. Act: Report the user a third time, which should trigger the ban.
	_ = reportService.CreateReport(4, victim.ID, 0, "user", "Harassment 3")

	// 5. Assert: Check that the user IS now banned.
	isBanned, _ = authService.CheckBlacklist(victim.Run)
	if !isBanned {
		t.Error("User was NOT banned after 3 reports (security failure).")
	}
}
