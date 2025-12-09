package main

import (
	"log"
	"os"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"       // Ajustar Import
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"   // Ajustar Import
	transport "github.com/RicketyMajor/PAWS-2.0/internal/transport/http" // Ajustar Import (alias transport)
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"github.com/RicketyMajor/PAWS-2.0/internal/transport/http/middleware"
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
	petService := services.NewPetService()
	fileService := services.NewFileService()
	identityService := services.NewIdentityService()

	authHandler := transport.NewAuthHandler(authService)
	petHandler := transport.NewPetHandler(petService)
	uploadHandler := transport.NewUploadHandler(fileService)
	identityHandler := transport.NewIdentityHandler(identityService)

	// 3. Configurar Router (Gin)
	r := gin.Default()

	r.Static("/uploads", "./uploads")

	// Definir Rutas
	api := r.Group("/api/v1") // Versionamiento de API (Buena práctica)
	{
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}
		pets := api.Group("/pets")
        pets.Use(middleware.AuthMiddleware()) // <--- AQUÍ APLICAMOS EL "PORTERO"
        {
            pets.POST("", petHandler.Create)  // POST /api/v1/pets
            pets.GET("", petHandler.GetAll)   // GET /api/v1/pets
        }
		files := api.Group("/files")
        files.Use(middleware.AuthMiddleware()) // Solo usuarios logueados pueden subir fotos
        {
            files.POST("/upload", uploadHandler.Upload)
        }
		verification := api.Group("/verification")
        verification.Use(middleware.AuthMiddleware()) // Solo logueados
        {
            verification.POST("/verify", identityHandler.Verify)
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