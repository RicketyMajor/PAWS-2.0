// Package database provides database connection and migration functionality.
package database

import (
	"log"
	"os"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

// DB is the global database connection pool.
var DB *gorm.DB

// Connect initializes the connection to the PostgreSQL database.
func Connect() {
	dsn := os.Getenv("DATABASE_URL")
	
	if dsn == "" {
		log.Fatal("FATAL: DATABASE_URL environment variable not found.")
	}

	log.Println("Connecting to Database...")

	config := &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	}

	connection, err := gorm.Open(postgres.Open(dsn), config)
	if err != nil {
		log.Fatal("Fatal error connecting to database: ", err)
	}

	DB = connection
	log.Println("Database connection successful.")
}

// Migrate runs the GORM auto-migration for the application's domain models.
// NOTE: This function is currently not being called. Migrations are handled
// directly in the `main` function in `cmd/api/main.go`.
func Migrate() {
	err := DB.AutoMigrate(
		&domain.User{}, 
		&domain.UserProfile{}, 
		&domain.Pet{}, 
		&domain.Match{},
		&domain.Message{}, 
		&domain.Report{},
		&domain.Review{},
		&domain.BlacklistEntry{},
	)
	
	if err != nil {
		log.Fatal("Critical error during DB migration:", err)
	}
	log.Println("Migration completed successfully.")
}