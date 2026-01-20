package main

import (
	"log"
	"os"
	"fmt"
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
	
	if err := godotenv.Load(); err != nil {
		log.Println("Info: No se encontró archivo .env, usando variables del sistema")
	}
    url := os.Getenv("DATABASE_URL")
    if url != "" {
        log.Println("DEBUG: ¡Variable DATABASE_URL encontrada! Longitud:", len(url))
    } else {
        log.Println("DEBUG: DATABASE_URL está vacía. Godotenv cargó el archivo pero no leyó la variable.")
    }

	database.Connect()

	// Migraciones
	if err := database.DB.AutoMigrate(
		&domain.User{}, 
		&domain.UserProfile{},
		&domain.Pet{},
		&domain.PetImage{},
		&domain.Match{},
		&domain.Message{}, 
		&domain.Review{},
		&domain.Report{},
		&domain.BlacklistEntry{},
	); err != nil {
		log.Fatal("Error crítico migrando BD:", err)
	}

	// =========================================================================
	// SEEDER DE ADMIN
	// =========================================================================
	var adminUser domain.User
	targetEmail := "alonso.vera@mail.udp.cl"

	if err := database.DB.Where("email = ?", targetEmail).First(&adminUser).Error; err == nil {
		if adminUser.Role != "admin" {
			database.DB.Model(&adminUser).Update("role", "admin")
			log.Printf("Usuario %s promovido a ADMIN.", targetEmail)
		} else {
			log.Println("El usuario Admin ya está configurado correctamente.")
		}
	} else {
		log.Printf("AVISO: El usuario %s aún no existe en la BD.", targetEmail)
	}

	// -------------------------------------------------------------------------
	// KILL SWITCH: RabbitMQ & Async
	// -------------------------------------------------------------------------
	var mqClient *messaging.RabbitMQClient
	var err error
	
	rabbitUser := os.Getenv("RABBITMQ_USER")
	rabbitPass := os.Getenv("RABBITMQ_PASSWORD")
	rabbitHost := os.Getenv("RABBITMQ_HOST")
	rabbitPort := os.Getenv("RABBITMQ_PORT")

	if rabbitUser == "" { rabbitUser = "guest" }
	if rabbitPass == "" { rabbitPass = "guest" }
	if rabbitHost == "" { rabbitHost = "localhost" }
	if rabbitPort == "" { rabbitPort = "5672" }

	rabbitURL := fmt.Sprintf("amqp://%s:%s@%s:%s/", rabbitUser, rabbitPass, rabbitHost, rabbitPort)

	if os.Getenv("ENABLE_ASYNC_FEATURES") == "true" {
		log.Printf("Intentando conectar a RabbitMQ en: %s:%s...", rabbitHost, rabbitPort)
		mqClient, err = messaging.ConnectRabbitMQ(rabbitURL)
		if err != nil {
			log.Printf("RabbitMQ error: %v. \nEl sistema funcionará en MODO SÍNCRONO.", err)
		} else {
			defer mqClient.Close()
			log.Println("Conectado a RabbitMQ")
		}
	} else {
		log.Println("ℹAsync Features desactivadas. Usando modo síncrono.")
	}

	emailClient := email.NewEmailClient()

	if mqClient != nil {
		workers.StartEmailConsumer(mqClient, emailClient)
		workers.StartNotificationConsumer(mqClient, database.DB)
	}

	// =========================================================================
	// 2. INYECCIÓN DE DEPENDENCIAS
	// =========================================================================

	otpService      := services.NewOTPService(mqClient) 
	authService     := services.NewAuthService(database.DB)
	petService      := services.NewPetService(database.DB)
	userService     := services.NewUserService(database.DB)
	chatService     := services.NewChatService(database.DB)
	reviewService   := services.NewReviewService(database.DB)
	fileService     := services.NewFileService()
	identityService := services.NewIdentityService()

	reportService   := services.NewReportService(database.DB, authService)
	matchService    := services.NewMatchService(database.DB, petService, mqClient)

	hub := httpTransport.NewHub(chatService, mqClient)
	go hub.Run()

	// =========================================================================
	// 3. HANDLERS
	// =========================================================================

	authHandler     := httpTransport.NewAuthHandler(authService, otpService)
	petHandler 		:= httpTransport.NewPetHandler(petService, fileService)
	userHandler     := httpTransport.NewUserHandler(userService, matchService)
	matchHandler    := httpTransport.NewMatchHandler(matchService)
	socialHandler   := httpTransport.NewSocialHandler(chatService, reviewService)
	reportHandler   := httpTransport.NewReportHandler(reportService)
	uploadHandler   := httpTransport.NewUploadHandler(fileService)
	identityHandler := httpTransport.NewIdentityHandler(identityService)
	wsHandler       := httpTransport.NewWSHandler(hub)
	adminHandler    := httpTransport.NewAdminHandler(reportService)
	notificationHandler := httpTransport.NewNotificationHandler(userService)

	// =========================================================================
	// 4. RUTAS & MIDDLEWARE
	// =========================================================================

	r := gin.Default()
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

		// BUSCADOR PÚBLICO DE BLACKLIST
		api.GET("/blacklist/search", reportHandler.SearchBlacklist)
		
		petsPublic := api.Group("/pets")
		{
			petsPublic.GET("", petHandler.GetAll)
			petsPublic.GET("/:id", petHandler.GetPetByID)
			petsPublic.GET("/nearby", petHandler.GetNearby)
		}

		// RUTAS PROTEGIDAS
		protected := api.Group("/")
		protected.Use(middleware.AuthMiddleware()) 
		{
			protected.PUT("/profile", userHandler.UpdateProfile)
			protected.GET("/profile", userHandler.GetProfile)
			protected.POST("/pets", petHandler.Create)
			protected.POST("/files/upload", uploadHandler.Upload)
			protected.DELETE("/pets/:id", petHandler.Delete)
			protected.POST("/notifications/token", notificationHandler.UpdateToken)

			match := protected.Group("/matches")
			{
				match.GET("/candidates", matchHandler.GetMatches)
				match.POST("/swipe", matchHandler.Swipe)
				match.GET("/requests", matchHandler.GetPending)
				match.POST("/respond", matchHandler.Respond)
				match.GET("/:id/messages", socialHandler.GetChatHistory)
				match.GET("/rescuer", matchHandler.GetRescuerMatches)
				match.GET("/adopter", matchHandler.GetAdopterMatches)
				match.POST("/unmatch", matchHandler.Unmatch)
			}

			protected.POST("/reviews", socialHandler.CreateReview)
			protected.POST("/report", reportHandler.Create)

			protected.GET("/ws", wsHandler.HandleConnections)
		}

		// ADMIN
		admin := protected.Group("/admin")
		admin.Use(middleware.RequireRole("admin")) 
		{
			admin.GET("/reports", adminHandler.GetReports)       
			admin.GET("/reports/:id", adminHandler.GetReportDetails) 
			admin.POST("/reports/:id/resolve", adminHandler.Resolve) 
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