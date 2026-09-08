// Package database provides database connection and migration functionality.
package database

import (
	"context"
	"io"
	"log"
	"os"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

// DB is the global database connection pool.
var DB *gorm.DB

// queryLogger builds GORM's logger with the bind parameters left out of the
// output. GORM's Explain interpolates them into the statement before printing
// it, which puts national ids, emails and GPS coordinates in the log;
// ParameterizedQueries empties the parameters first, so the line keeps the
// statement, its latency and its row count and drops the values.
//
// ParameterizedQueries alone is not enough: Scan swaps this logger out for
// logger.Recorder while it executes and hands back an already-interpolated
// string, so the filter above never runs on that path — and GetNearby, the
// coordinate query this exists for, is a Scan. RecorderParamsFilter is the same
// switch for the recorder, and it is package-global because the recorder is.
//
// Anything that routes around both still leaks: .Debug() installs logger.Default
// at Info with neither flag set, which reinstates the bug for that statement.
func queryLogger(out io.Writer) logger.Interface {
	logger.RecorderParamsFilter = func(_ context.Context, sql string, _ ...interface{}) (string, []interface{}) {
		return sql, nil
	}

	return logger.New(log.New(out, "\r\n", log.LstdFlags), logger.Config{
		SlowThreshold:        200 * time.Millisecond,
		LogLevel:             logger.Info,
		Colorful:             true,
		ParameterizedQueries: true,
	})
}

// Connect initializes the connection to the PostgreSQL database.
func Connect() {
	dsn := os.Getenv("DATABASE_URL")

	if dsn == "" {
		log.Fatal("FATAL: DATABASE_URL environment variable not found.")
	}

	log.Println("Connecting to Database...")

	config := &gorm.Config{
		Logger: queryLogger(os.Stdout),
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
