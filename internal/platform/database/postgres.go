package database

import (
	"log"
	"os"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

var DB *gorm.DB

func Connect() {
	dsn := os.Getenv("DATABASE_URL")
	
	if dsn == "" {
		log.Fatal("DATABASE_URL no encontrada en variables de entorno")
	}

	log.Println("Conectando a Base de Datos (Modo Session/Direct)...")

	// Configuración estándar para puerto 5432
	config := &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	}

	connection, err := gorm.Open(postgres.Open(dsn), config)
	if err != nil {
		log.Fatal("Error fatal conectando a la base de datos: ", err)
	}

	DB = connection
	log.Println("Conexión Exitosa")
}

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
		log.Fatal("Error crítico migrando BD:", err)
	}
	log.Println("Migración completada")
}