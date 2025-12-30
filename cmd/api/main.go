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
	database.DB.Migrator().DropTable(&domain.Report{}) // SOLO para desarrollo, elimina en producción
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

	// =========================================================================
	// SEEDER DE ADMIN (Auto-Promoción)
	// =========================================================================
	var adminUser domain.User
	targetEmail := "alonso.vera@mail.udp.cl"

	// Buscamos si el usuario ya se registró
	if err := database.DB.Where("email = ?", targetEmail).First(&adminUser).Error; err == nil {
		// Si existe y no es admin, lo promovemos
		if adminUser.Role != "admin" {
			database.DB.Model(&adminUser).Update("role", "admin")
			log.Printf("Usuario %s promovido a ADMIN.", targetEmail)
		} else {
			log.Println("El usuario Admin ya está configurado correctamente.")
		}
	} else {
		log.Printf("AVISO: El usuario %s aún no existe en la BD. Regístrate en la App y reinicia el backend.", targetEmail)
	}
	// =========================================================================

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

	// WebSocket Hub
	hub := httpTransport.NewHub(chatService) 
	go hub.Run()

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
	wsHandler       := httpTransport.NewWSHandler(hub)
	adminHandler    := httpTransport.NewAdminHandler(reportService)

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
			protected.GET("/profile", userHandler.GetProfile)
			protected.POST("/pets", petHandler.Create)
			protected.POST("/files/upload", uploadHandler.Upload)
			protected.DELETE("/pets/:id", petHandler.Delete)

			match := protected.Group("/matches")
			{
				match.GET("/candidates", matchHandler.GetMatches)
				match.POST("/swipe", matchHandler.Swipe)
				match.GET("/requests", matchHandler.GetPending)
				match.POST("/respond", matchHandler.Respond)
				match.GET("/:id/messages", socialHandler.GetChatHistory)
				match.GET("/mine", matchHandler.GetMyMatches)
				match.GET("/mine/pending", matchHandler.GetMyPending)
				match.GET("/rescuer", matchHandler.GetRescuerMatches)
			}

			protected.POST("/reviews", socialHandler.CreateReview)
			protected.POST("/report", reportHandler.Create)

			// WebSocket unificado
			protected.GET("/ws", wsHandler.HandleConnections)
		}

		// GRUPO ADMIN: Doble protección (Auth + Role Admin)
		admin := protected.Group("/admin")
		admin.Use(middleware.RequireRole("admin")) 
		{
			admin.GET("/reports", adminHandler.GetReports)
			admin.POST("/ban/:id", adminHandler.BanUser)
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