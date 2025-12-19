package main

import (
	"log"
	"os"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
	
	// Unificamos el alias a 'httpTransport' para evitar duplicados
	httpTransport "github.com/RicketyMajor/PAWS-2.0/internal/transport/http" 
	"github.com/RicketyMajor/PAWS-2.0/internal/transport/http/middleware"
	"github.com/RicketyMajor/PAWS-2.0/internal/transport/websocket"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// 1. Configuración inicial
	if err := godotenv.Load(); err != nil {
		log.Println("No se encontró archivo .env, usando variables de entorno del sistema")
	}

	database.Connect()

	// 2. Inyección de Dependencias (ORDEN CORREGIDO)
	
	// A. Servicios Base (Independientes)
	authService := services.NewAuthService(nil) // Creamos este PRIMERO
	petService := services.NewPetService()
	fileService := services.NewFileService()
	identityService := services.NewIdentityService()
	
	// B. Migraciones y Servicios Dependientes
	// Agregamos Report a la migración
	database.DB.AutoMigrate(&domain.User{}, &domain.BlacklistEntry{}, &domain.Report{}) 
	
	// ReportService necesita authService, por eso va después
	reportService := services.NewReportService(database.DB, authService) 
	matchService := services.NewMatchService(petService)
	
	// C. Websocket Hub
	hub := websocket.NewHub()
	go hub.Run()

	// 3. Inicialización de Handlers (Usando el alias unificado httpTransport)
	authHandler := httpTransport.NewAuthHandler(authService)
	petHandler := httpTransport.NewPetHandler(petService)
	uploadHandler := httpTransport.NewUploadHandler(fileService)
	identityHandler := httpTransport.NewIdentityHandler(identityService)
	matchHandler := httpTransport.NewMatchHandler(matchService)
	wsHandler := httpTransport.NewWSHandler(hub)
	reportHandler := httpTransport.NewReportHandler(reportService)

	// 4. Configurar Router (Gin)
	r := gin.Default()
	r.Static("/uploads", "./uploads") // Servir imágenes estáticas

	api := r.Group("/api/v1")
	{
		// ----------------------------
		// RUTAS PÚBLICAS (Sin Token)
		// ----------------------------
		
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}

		// Mascotas (Lectura)
		petsPublic := api.Group("/pets")
		{
			petsPublic.GET("/search", petHandler.Search)
			petsPublic.GET("/match", matchHandler.GetMatches)
			petsPublic.GET("", petHandler.GetAll)
		}

		// Verificación de Identidad (Pública para registro)
		verification := api.Group("/verification")
		{
			verification.POST("/verify", identityHandler.Verify)
		}

		// ----------------------------
		// RUTAS PROTEGIDAS (Con Token)
		// ----------------------------
		
		// Grupo general protegido
		protected := api.Group("/")
		protected.Use(middleware.AuthMiddleware()) // <--- IMPORTANTE: Descomentado para seguridad
		{
			// Reportes (Requiere saber quién reporta)
			protected.POST("/report", reportHandler.Create)
			
			// Archivos
			protected.POST("/files/upload", uploadHandler.Upload)
		}

		// Mascotas (Escritura)
		petsProtected := api.Group("/pets")
		petsProtected.Use(middleware.AuthMiddleware())
		{
			petsProtected.POST("", petHandler.Create)
		}

		// Chat
		chat := api.Group("/chat")
		chat.Use(middleware.AuthMiddleware())
		{
			chat.GET("/ws", wsHandler.HandleConnections)
		}
	}

	// 5. Arrancar Servidor
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("🚀 Servidor PAWS corriendo en puerto %s", port)
	r.Run(":" + port)
}