package database

import (
	"fmt"
	"log"
	"os"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	// Ajusta este import si tu ruta es diferente, pero mantenlo apuntando a tu dominio
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	
)

// DB es una variable global (por ahora) que guardará la conexión.
var DB *gorm.DB

// Connect inicializa la conexión a PostgreSQL (Soporta URL completa o variables individuales)
func Connect() {
	var dsn string

	// 1. PRIORIDAD: Intentamos leer la Connection String completa (Estilo Supabase/Railway)
	// Ejemplo: postgres://postgres:password@db.supabase.co:5432/postgres
	dsn = os.Getenv("DATABASE_URL")

	// 2. FALLBACK: Si no hay URL completa, construimos la cadena manualmente (Estilo Local/Docker)
	if dsn == "" {
		host := os.Getenv("DB_HOST")
		user := os.Getenv("DB_USER")
		password := os.Getenv("DB_PASSWORD")
		dbName := os.Getenv("DB_NAME")
		port := os.Getenv("DB_PORT")
		
		sslMode := os.Getenv("DB_SSL_MODE")
		if sslMode == "" {
			sslMode = "disable"
		}

		dsn = fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=%s",
			host, user, password, dbName, port, sslMode)
		
		log.Println("Modo Local detectado: Usando variables individuales.")
	} else {
		log.Println("Modo Nube detectado: Usando DATABASE_URL.")
	}

	connection, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		PrepareStmt: false,
	})
	if err != nil {
		log.Fatal("Error fatal conectando a la base de datos: ", err)
	}

	DB = connection
	log.Println("Conexión a Base de Datos exitosa")
}

// Migrate ejecuta las migraciones automáticas
func Migrate() {
	// Asegúrate de incluir TODOS tus modelos aquí
	// Nota: Agregué Report y Review que hicimos en etapas anteriores
	err := DB.AutoMigrate(
		&domain.User{}, 
		&domain.UserProfile{}, 
		&domain.Pet{}, 
		&domain.BlacklistEntry{},
		&domain.Match{},
		&domain.Message{},
		&domain.Report{},
		&domain.Review{},
	)
	
	if err != nil {
		log.Fatal("Error en la migración de base de datos: ", err)
	}
	log.Println("Migración de base de datos completada")
}