package main

import (
	"log"
	"os"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/workers"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/email"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
	
	httpTransport "github.com/RicketyMajor/PAWS-2.0/internal/transport/http"
	"github.com/RicketyMajor/PAWS-2.0/internal/transport/http/middleware"
	
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// =========================================================================
	// 1. CONFIGURACIÓN E INFRAESTRUCTURA
	// =========================================================================
	
	// Cargar variables de entorno
	if err := godotenv.Load(); err != nil {
		log.Println("Info: No se encontró archivo .env, usando variables del sistema")
	}

	// Conexión a Base de Datos
	database.Connect()

	// Migraciones (Esquema completo)
	if err := database.DB.AutoMigrate(
		&domain.User{}, 
		&domain.UserProfile{},
		&domain.Pet{},
		&domain.Match{},
		&domain.Message{}, 
		&domain.Review{},
		&domain.Report{},
		&domain.BlacklistEntry{},
	); err != nil {
		log.Fatal("Error crítico migrando BD:", err)
	}

	// RabbitMQ (Messaging)
	mqClient, err := messaging.ConnectRabbitMQ("amqp://guest:guest@rabbitmq-service:5672/")
	if err != nil {
		log.Println("RabbitMQ no disponible. El sistema funcionará, pero sin eventos asíncronos (OTP en logs).")
	} else {
		defer mqClient.Close()
		log.Println("Conectado a RabbitMQ")
	}

	// Cliente de Email (SendGrid)
	emailClient := email.NewEmailClient()

	// Worker de Email (Consumidor)
	if mqClient != nil {
		workers.StartEmailConsumer(mqClient, emailClient)
	}

	// WebSocket Hub (Motor de chat)
	hub := httpTransport.NewHub()
	go hub.Run()

	// =========================================================================
	// 2. INYECCIÓN DE DEPENDENCIAS (SERVICIOS)
	// =========================================================================

	// Nivel 1: Servicios Base
	otpService      := services.NewOTPService(mqClient)
	authService     := services.NewAuthService(database.DB) // Asumimos que requiere DB
	petService      := services.NewPetService(database.DB)
	userService     := services.NewUserService(database.DB)
	chatService     := services.NewChatService(database.DB)
	reviewService   := services.NewReviewService(database.DB)
	fileService     := services.NewFileService()
	identityService := services.NewIdentityService()

	// Nivel 2: Servicios Compuestos (Dependen de otros)
	reportService   := services.NewReportService(database.DB, authService)
	matchService    := services.NewMatchService(database.DB, petService)

	// =========================================================================
	// 3. HANDLERS (CONTROLADORES HTTP)
	// =========================================================================

	authHandler     := httpTransport.NewAuthHandler(authService, otpService)
	petHandler      := httpTransport.NewPetHandler(petService)
	userHandler     := httpTransport.NewUserHandler(userService, matchService)
	matchHandler    := httpTransport.NewMatchHandler(matchService)
	socialHandler   := httpTransport.NewSocialHandler(chatService, reviewService)
	reportHandler   := httpTransport.NewReportHandler(reportService)
	uploadHandler   := httpTransport.NewUploadHandler(fileService)
	identityHandler := httpTransport.NewIdentityHandler(identityService)
	
	// WebSocket Handler (Inyectamos Hub y ChatService para persistencia)
	wsHandler       := httpTransport.NewWSHandler(hub, chatService)

	// =========================================================================
	// 4. RUTAS (ROUTER)
	// =========================================================================

	r := gin.Default()
	r.Static("/uploads", "./uploads") // Servir imágenes

	api := r.Group("/api/v1")
	{
		// ---------------------------------------------------------------------
		// A. RUTAS PÚBLICAS (Sin Token)
		// ---------------------------------------------------------------------
		
		// Auth & OTP
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/otp/request", authHandler.RequestOTP) // Asumiendo que RequestOTP está en AuthHandler u OTPHandler
			auth.POST("/otp/verify", authHandler.VerifyOTP)
		}

		// Verificación de Identidad (Registro)
		api.POST("/verification/verify", identityHandler.Verify)

		// Mascotas (Lectura y Búsqueda)
		petsPublic := api.Group("/pets")
		{
			petsPublic.GET("", petHandler.GetAll)           // Listar con filtros básicos
			petsPublic.GET("/:id", petHandler.GetPetByID)   // Ver detalle
			petsPublic.GET("/nearby", petHandler.GetNearby) // Geo-búsqueda (PostGIS/Haversine)
		}

		// ---------------------------------------------------------------------
		// B. RUTAS PROTEGIDAS (Con Token JWT)
		// ---------------------------------------------------------------------
		
		protected := api.Group("/")
		protected.Use(middleware.AuthMiddleware())
		{
			// Usuario
			protected.PUT("/profile", userHandler.UpdateProfile)

			// Mascotas (Escritura)
			protected.POST("/pets", petHandler.Create) // Publicar mascota

			// Archivos
			protected.POST("/files/upload", uploadHandler.Upload)

			// Matchmaking (Tinder Logic)
			match := protected.Group("/matches")
			{
				match.GET("/candidates", userHandler.GetSwipeDeck) // Obtener cartas
				match.POST("/swipe", matchHandler.Swipe)           // Dar Like/Dislike
				match.GET("/requests", matchHandler.GetPending)    // Ver quién me dio like
				match.POST("/respond", matchHandler.Respond)       // Aceptar/Rechazar match
				match.GET("/:id/messages", socialHandler.GetChatHistory) // Historial de chat
			}

			// Social & Comunidad
			protected.POST("/reviews", socialHandler.CreateReview)
			protected.POST("/report", reportHandler.Create)

			// WebSocket (Chat Realtime)
			// Unificado en una sola ruta estándar
			protected.GET("/ws", wsHandler.HandleConnections)
		}
	}

	// =========================================================================
	// 5. ARRANCAR
	// =========================================================================
	
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Servidor PAWS iniciado en puerto %s", port)
	
	if err := r.Run(":" + port); err != nil {
		log.Fatal("Error fatal en servidor:", err)
	}
}