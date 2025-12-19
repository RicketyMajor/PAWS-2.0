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
	"github.com/RicketyMajor/PAWS-2.0/internal/transport/websocket"
)

func main() {
	// 1. Configuración inicial
	// CÓDIGO CORREGIDO (RESILIENTE)
	if err := godotenv.Load(); err != nil {
		log.Println("No se encontró archivo .env, usando variables de entorno del sistema")
	}

	database.Connect()
	database.Migrate()

	// 2. Inyección de Dependencias
	// Inicializamos el servicio y el handler
	authService := services.NewAuthService(database.DB)
	petService := services.NewPetService()
	fileService := services.NewFileService()
	identityService := services.NewIdentityService()
	matchService := services.NewMatchService(petService)
	hub := websocket.NewHub()
	go hub.Run()

	authHandler := transport.NewAuthHandler(authService)
	petHandler := transport.NewPetHandler(petService)
	uploadHandler := transport.NewUploadHandler(fileService)
	identityHandler := transport.NewIdentityHandler(identityService)
	matchHandler := transport.NewMatchHandler(matchService)
	wsHandler := transport.NewWSHandler(hub)
	

	// 3. Configurar Router (Gin)
r := gin.Default()
	r.Static("/uploads", "./uploads")

	api := r.Group("/api/v1")
	{
		// ----------------------------
		// RUTAS PÚBLICAS (Sin Token)
		// ----------------------------
		
		// Auth
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}

		// Mascotas (Lectura)
		// Creamos un grupo para las rutas GET que cualquiera puede ver
		petsPublic := api.Group("/pets")
		{
			petsPublic.GET("/search", petHandler.Search) // Buscador
			petsPublic.GET("/match", matchHandler.GetMatches)
			petsPublic.GET("", petHandler.GetAll)        // Ver todas
		}

		// ----------------------------
		// RUTAS PROTEGIDAS (Con Token)
		// ----------------------------
		
		// Mascotas (Escritura)
		// Usamos el MISMO prefijo "/pets" pero en un grupo diferente con middleware
		petsProtected := api.Group("/pets")
		petsProtected.Use(middleware.AuthMiddleware())
		{
			petsProtected.POST("", petHandler.Create) // Crear (Solo usuarios)
		}

		// Archivos
		files := api.Group("/files")
		files.Use(middleware.AuthMiddleware())
		{
			files.POST("/upload", uploadHandler.Upload)
		}

		// Verificación de Identidad
		verification := api.Group("/verification")
		verification.Use(middleware.AuthMiddleware())
		{
			verification.POST("/verify", identityHandler.Verify)
		}

		chat := api.Group("/chat")
        chat.Use(middleware.AuthMiddleware())
        {
            chat.GET("/ws", wsHandler.HandleConnections) // Endpoint WebSocket
        }
	}

	// 4. Arrancar Servidor
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf(" Servidor PAWS corriendo en puerto %s", port)
	r.Run(":" + port)
}