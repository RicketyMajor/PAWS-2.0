package main

import (
	"log"
	"os"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"       // Ajustar Import
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"   // Ajustar Import
	transport "github.com/RicketyMajor/PAWS-2.0/internal/transport/http" // Ajustar Import (alias transport)
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// 1. Configuración inicial
	if err := godotenv.Load(); err != nil {
		log.Fatal("Error cargando .env")
	}

	database.Connect()
	database.Migrate()

	// 2. Inyección de Dependencias
	// Inicializamos el servicio y el handler
	authService := services.NewAuthService()
	authHandler := transport.NewAuthHandler(authService)

	// 3. Configurar Router (Gin)
	r := gin.Default()

	// Definir Rutas
	api := r.Group("/api/v1") // Versionamiento de API (Buena práctica)
	{
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}
	}

	// 4. Arrancar Servidor
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("🚀 Servidor PAWS corriendo en puerto %s", port)
	r.Run(":" + port)
}