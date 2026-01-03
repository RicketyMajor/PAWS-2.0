package database

import (
	"fmt"
	"log"
	"os"
	"strings"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger" // Importante para ver logs limpios

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

var DB *gorm.DB

func Connect() {
	// 1. Obtener la URL base
	dsn := os.Getenv("DATABASE_URL")
	
	// Si no hay URL directa, construimos la local (Fallback)
	if dsn == "" {
		dsn = fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=%s",
			os.Getenv("DB_HOST"), 
			os.Getenv("DB_USER"), 
			os.Getenv("DB_PASSWORD"), 
			os.Getenv("DB_NAME"), 
			os.Getenv("DB_PORT"), 
			"disable",
		)
		log.Println("Modo Local detectado (Variables individuales)")
	} else {
		log.Println("Modo Nube detectado (DATABASE_URL)")
	}

	// --------------------------------------------------------------------
	//  LIMPIEZA Y FORZADO DE PROTOCOLO (FIX SUPABASE 6543)
	// --------------------------------------------------------------------
	// 1. Quitamos cualquier parámetro conflictivo antiguo si existiera
	if strings.Contains(dsn, "pgbouncer=true") {
		dsn = strings.ReplaceAll(dsn, "pgbouncer=true", "")
	}

	// 2. Aseguramos que 'prefer_simple_protocol' esté presente
	if !strings.Contains(dsn, "prefer_simple_protocol=true") {
		if strings.Contains(dsn, "?") {
			dsn += "&prefer_simple_protocol=true"
		} else {
			dsn += "?prefer_simple_protocol=true"
		}
	}
	// --------------------------------------------------------------------

	log.Println("Conectando con protocolo simple (Sin Caché)...")

	// 3. Configuración GORM
	config := &gorm.Config{
		PrepareStmt: false, // APAGADO OBLIGATORIO
		Logger:      logger.Default.LogMode(logger.Info), // Logs detallados para debug
	}

	connection, err := gorm.Open(postgres.Open(dsn), config)
	if err != nil {
		log.Fatal("Error fatal conectando a la base de datos: ", err)
	}

	DB = connection
	log.Println("Conexión a Base de Datos exitosa y estabilizada")
}

func Migrate() {
	// Ejecutamos la migración
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
	log.Println("Migración de base de datos completada sin errores")
}