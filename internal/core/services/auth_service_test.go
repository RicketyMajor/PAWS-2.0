// Package services_test contains unit tests for the services package.
package services

import (
	"testing"
	"github.com/glebarez/sqlite" // Lightweight in-memory SQL driver for tests
	"gorm.io/gorm"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

// setupTestDB creates an in-memory SQLite database and migrates the necessary tables.
func setupTestDB() *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		panic("Failed to connect to test database: " + err.Error())
	}
	if err := db.AutoMigrate(&domain.BlacklistEntry{}); err != nil {
        panic("Failed to migrate test database: " + err.Error())
    }
    return db
}

// TestCheckBlacklist tests the blacklist checking logic.
func TestCheckBlacklist(t *testing.T) {
	// 1. Arrange: Set up the mock database.
	db := setupTestDB()
	
	// Insert a test record into the mock database.
	bannedRun := "12345678-9"
	db.Create(&domain.BlacklistEntry{Run: bannedRun, Reason: "Animal Abuse"})

	// Initialize the service with the mock database.
	service := NewAuthService(db)

	// 2. Act & Assert: Define and run test cases.

	// Test Case 1: A banned RUN.
	t.Run("should return TRUE if the RUN is in the blacklist", func(t *testing.T) {
		isBanned, err := service.CheckBlacklist(bannedRun)
		if err != nil {
			t.Errorf("Unexpected error: %v", err)
		}
		if !isBanned {
			t.Error("Failed: Expected user to be banned, but was not.")
		}
	})

	// Test Case 2: A clean RUN.
	t.Run("should return FALSE if the RUN is not in the blacklist", func(t *testing.T) {
		cleanRun := "11111111-1"
		isBanned, err := service.CheckBlacklist(cleanRun)
		if err != nil {
			t.Errorf("Unexpected error: %v", err)
		}
		if isBanned {
			t.Error("Failed: Expected user not to be banned, but was.")
		}
	})

	// Test Case 3: An empty RUN.
	t.Run("should return an error if the RUN is empty", func(t *testing.T) {
		_, err := service.CheckBlacklist("")
		if err == nil {
			t.Error("Failed: Expected an error for an empty RUN, but got none.")
		}
	})
}