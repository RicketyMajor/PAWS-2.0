package main

import (
	"fmt"
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
	"gorm.io/gorm"
)

// dropLegacyConstraints elimina índices antiguos que impiden la duplicidad de RUT/Email
func dropLegacyConstraints(db *gorm.DB) {
	// Intentamos borrar los índices únicos globales antiguos.
	// Si no existen, no pasa nada (por eso el 'IF EXISTS').
	queries := []string{
		"DROP INDEX IF EXISTS idx_users_run;",
		"DROP INDEX IF EXISTS idx_users_email;",
		"DROP INDEX IF EXISTS uni_users_run;",   // Nombre alternativo común de GORM
		"DROP INDEX IF EXISTS uni_users_email;", // Nombre alternativo común de GORM
	}

	log.Println("MIGRACIÓN: Limpiando restricciones antiguas de base de datos...")
	for _, q := range queries {
		if err := db.Exec(q).Error; err != nil {
			log.Printf("Advertencia borrando índice (%s): %v", q, err)
		}
	}
	log.Println("Limpieza de índices completada.")
}

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

	// --- CORRECCIÓN BASE DE DATOS ---
	// Ejecutamos la limpieza ANTES de la migración automática
	dropLegacyConstraints(database.DB)

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
	
	// --- CAMBIO: Usamos nuestro Middleware Local para solucionar el error de Vercel (401/CORS) ---
	r.Use(LocalCORSMiddleware()) 
	
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
			protected.POST("/auth/switch-role", authHandler.SwitchRole)
			protected.PUT("/profile", userHandler.UpdateProfile)
			protected.GET("/profile", userHandler.GetProfile)
			protected.POST("/pets", petHandler.Create)
			protected.GET("/pets/my", petHandler.GetMyPets)
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
			protected.GET("/users/:id/reviews", socialHandler.GetUserReviews)
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

// --- NUEVA FUNCIÓN: Middleware CORS Robusto ---
// Esta función soluciona el problema de 401 en OPTIONS interceptando el Preflight.
func LocalCORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. Permitimos el origen dinámico (necesario para Vercel)
		origin := c.Request.Header.Get("Origin")
		if origin != "" {
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
		} else {
			// Fallback
			c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		}

		// 2. Permitimos credenciales y los headers necesarios (incluyendo Authorization)
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		// 3. ¡LA CLAVE! Si es OPTIONS, cortamos aquí con 204 y NO pasamos al AuthMiddleware
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}