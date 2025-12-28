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
	"github.com/RicketyMajor/PAWS-2.0/internal/transport/http/middleware" // Asegúrate que importe el paquete donde pusiste cors.go y auth.go
	
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// =========================================================================
	// 1. CONFIGURACIÓN E INFRAESTRUCTURA
	// =========================================================================
	
	if err := godotenv.Load(); err != nil {
		log.Println("Info: No se encontró archivo .env, usando variables del sistema")
	}

	database.Connect()

	// Migraciones
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

	// -------------------------------------------------------------------------
	// KILL SWITCH: RabbitMQ & Async (Etapa 1)
	// -------------------------------------------------------------------------
	var mqClient *messaging.RabbitMQClient
	var err error
	
	// Solo intentamos conectar si esta variable NO es "false"
	// Esto te permite trabajar en frontend sin levantar infraestructura pesada
	if os.Getenv("ENABLE_ASYNC_FEATURES") == "true" {
		mqClient, err = messaging.ConnectRabbitMQ("amqp://guest:guest@rabbitmq-service:5672/")
		if err != nil {
			log.Println("RabbitMQ error: El sistema funcionará en MODO SÍNCRONO (fallback).")
		} else {
			defer mqClient.Close()
			log.Println("Conectado a RabbitMQ (Modo Asíncrono Activado)")
		}
	} else {
		log.Println("Async Features desactivadas (ENABLE_ASYNC_FEATURES != true). Usando modo síncrono simple.")
	}

	emailClient := email.NewEmailClient()

	// Worker solo arranca si hay conexión real
	if mqClient != nil {
		workers.StartEmailConsumer(mqClient, emailClient)
	}

	// WebSocket Hub
	hub := httpTransport.NewHub()
	go hub.Run()

	// =========================================================================
	// 2. INYECCIÓN DE DEPENDENCIAS
	// =========================================================================

	// IMPORTANTE: Los servicios deben saber manejar mqClient == nil
	otpService      := services.NewOTPService(mqClient) 
	authService     := services.NewAuthService(database.DB)
	petService      := services.NewPetService(database.DB)
	userService     := services.NewUserService(database.DB)
	chatService     := services.NewChatService(database.DB)
	reviewService   := services.NewReviewService(database.DB)
	fileService     := services.NewFileService()
	identityService := services.NewIdentityService()

	reportService   := services.NewReportService(database.DB, authService)
	matchService    := services.NewMatchService(database.DB, petService)

	// =========================================================================
	// 3. HANDLERS
	// =========================================================================

	authHandler     := httpTransport.NewAuthHandler(authService, otpService)
	petHandler      := httpTransport.NewPetHandler(petService)
	userHandler     := httpTransport.NewUserHandler(userService, matchService)
	matchHandler    := httpTransport.NewMatchHandler(matchService)
	socialHandler   := httpTransport.NewSocialHandler(chatService, reviewService)
	reportHandler   := httpTransport.NewReportHandler(reportService)
	uploadHandler   := httpTransport.NewUploadHandler(fileService)
	identityHandler := httpTransport.NewIdentityHandler(identityService)
	
	wsHandler       := httpTransport.NewWSHandler(hub, chatService)

	// =========================================================================
	// 4. RUTAS & MIDDLEWARE
	// =========================================================================

	r := gin.Default()
	
	// APLICAR CORS: Fundamental para Flutter Web
	r.Use(middleware.CORSMiddleware())

	r.Static("/uploads", "./uploads")

	api := r.Group("/api/v1")
	{
		// RUTAS PÚBLICAS
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/otp/request", authHandler.RequestOTP)
			auth.POST("/otp/verify", authHandler.VerifyOTP)
		}

		api.POST("/verification/verify", identityHandler.Verify)

		petsPublic := api.Group("/pets")
		{
			petsPublic.GET("", petHandler.GetAll)
			petsPublic.GET("/:id", petHandler.GetPetByID)
			petsPublic.GET("/nearby", petHandler.GetNearby)
		}

		// RUTAS PROTEGIDAS
		protected := api.Group("/")
		protected.Use(middleware.AuthMiddleware()) // Tu auth.go original
		{
			protected.PUT("/profile", userHandler.UpdateProfile)
			protected.POST("/pets", petHandler.Create)
			protected.POST("/files/upload", uploadHandler.Upload)
			protected.DELETE("/pets/:id", petHandler.Delete)

			match := protected.Group("/matches")
			{
				match.GET("/candidates", userHandler.GetSwipeDeck)
				match.POST("/swipe", matchHandler.Swipe)
				match.GET("/requests", matchHandler.GetPending)
				match.POST("/respond", matchHandler.Respond)
				match.GET("/:id/messages", socialHandler.GetChatHistory)
			}

			protected.POST("/reviews", socialHandler.CreateReview)
			protected.POST("/report", reportHandler.Create)

			// WebSocket unificado
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
	
	// En Web/Vercel no usamos localhost, usamos 0.0.0.0 implícitamente al omitir IP
	if err := r.Run(":" + port); err != nil {
		log.Fatal("Error fatal en servidor:", err)
	}
}