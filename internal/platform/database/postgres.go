package database

import (
	"fmt"
	"log"
	"os"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

// DB es una variable global (por ahora) que guardará la conexión.
// En fases futuras, inyectaremos esto como dependencia para hacerlo más limpio.
var DB *gorm.DB

// Connect inicializa la conexión a PostgreSQL usando las variables de entorno
func Connect() {
	host := os.Getenv("DB_HOST")
	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")
	port := os.Getenv("DB_PORT")
	
	// --- CAMBIO AQUÍ ---
	// Leemos la variable, pero si está vacía, forzamos "disable"
	sslMode := os.Getenv("DB_SSL_MODE")
	if sslMode == "" {
		sslMode = "disable"
	}
	// -------------------

	dsn := fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=%s",
		host, user, password, dbName, port, sslMode)

	connection, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal("Error conectando a la base de datos: ", err)
	}

	DB = connection
	log.Println("Conexión a Base de Datos exitosa")
}
func Migrate() {
	// Agregamos &domain.BlacklistEntry{} a la lista
	err := DB.AutoMigrate(&domain.User{}, &domain.BlacklistEntry{}, &domain.Pet{})
	if err != nil {
		log.Fatal("Error en la migración de base de datos: ", err)
	}
	log.Println("Migración de base de datos completada")
}