// Package main is the entry point of the PAWS Backend application.
package main

import (
	"log"
	"net/http"
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

// dropLegacyConstraints removes old unique indexes that might cause conflicts.
// This is a temporary migration helper function.
func dropLegacyConstraints(db *gorm.DB) {
	queries := []string{
		"DROP INDEX IF EXISTS idx_users_run;",
		"DROP INDEX IF EXISTS idx_users_email;",
		"DROP INDEX IF EXISTS uni_users_run;",
		"DROP INDEX IF EXISTS uni_users_email;",
	}

	log.Println("MIGRATION: Cleaning up old database constraints...")
	for _, q := range queries {
		if err := db.Exec(q).Error; err != nil {
			log.Printf("Warning while dropping index (%s): %v", q, err)
		}
	}
	log.Println("Index cleanup completed.")
}

func main() {
	// =========================================================================
	// Configuration & Infrastructure
	// =========================================================================

	// Load .env file if it exists
	if err := godotenv.Load(); err != nil {
		log.Println("Info: .env file not found, using system environment variables")
	}

	// Connect to the database
	database.Connect()

	// --- Database Migration ---
	// Run cleanup before auto-migration
	dropLegacyConstraints(database.DB)

	// Auto-migrate GORM models
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
		log.Fatal("Critical error during DB migration:", err)
	}

	// =========================================================================
	// Admin User Seeder
	// =========================================================================

	var adminUser domain.User
	targetEmail := "alonso.vera@mail.udp.cl"

	if err := database.DB.Where("email = ?", targetEmail).First(&adminUser).Error; err == nil {
		if adminUser.Role != "admin" {
			database.DB.Model(&adminUser).Update("role", "admin")
			log.Printf("User %s promoted to ADMIN.", targetEmail)
		} else {
			log.Println("Admin user is already correctly configured.")
		}
	} else {
		log.Printf("NOTICE: User %s does not exist in the DB yet.", targetEmail)
	}

	// =========================================================================
	// Async Feature Toggle (RabbitMQ)
	// =========================================================================
	var mqClient *messaging.RabbitMQClient
	var err error

	rabbitURL := os.Getenv("RABBITMQ_URL")
	if rabbitURL == "" {
		rabbitURL = "amqp://guest:guest@localhost:5672/" // Fallback for local dev
	}

	if os.Getenv("ENABLE_ASYNC_FEATURES") == "true" {
		log.Println("Attempting to connect to RabbitMQ...")
		mqClient, err = messaging.ConnectRabbitMQ(rabbitURL)
		if err != nil {
			log.Printf("RabbitMQ connection error: %v. System will run in SYNC MODE.", err)
		} else {
			log.Println("Successfully connected to RabbitMQ.")
		}
	} else {
		log.Println("Async features disabled. Using sync mode.")
	}

	emailClient := email.NewEmailClient()

	if mqClient != nil {
		// Start resilient workers in separate goroutines
		go workers.StartEmailConsumer(rabbitURL, emailClient)
		go workers.StartNotificationConsumer(rabbitURL, database.DB)
	}

	// =========================================================================
	// Dependency Injection
	// =========================================================================

	otpService := services.NewOTPService(mqClient, emailClient)
	authService := services.NewAuthService(database.DB)
	petService := services.NewPetService(database.DB)
	userService := services.NewUserService(database.DB)
	chatService := services.NewChatService(database.DB)
	reviewService := services.NewReviewService(database.DB)
	fileService := services.NewFileService()
	identityService := services.NewIdentityService()

	reportService := services.NewReportService(database.DB, authService)
	matchService := services.NewMatchService(database.DB, petService, mqClient)

	hub := httpTransport.NewHub(chatService, mqClient)
	go hub.Run()

	// =========================================================================
	// HTTP Handlers
	// =========================================================================

	authHandler := httpTransport.NewAuthHandler(authService, otpService)
	petHandler := httpTransport.NewPetHandler(petService, fileService)
	userHandler := httpTransport.NewUserHandler(userService, matchService)
	matchHandler := httpTransport.NewMatchHandler(matchService)
	socialHandler := httpTransport.NewSocialHandler(chatService, reviewService)
	reportHandler := httpTransport.NewReportHandler(reportService)
	uploadHandler := httpTransport.NewUploadHandler(fileService)
	identityHandler := httpTransport.NewIdentityHandler(identityService)
	wsHandler := httpTransport.NewWSHandler(hub)
	adminHandler := httpTransport.NewAdminHandler(reportService)
	notificationHandler := httpTransport.NewNotificationHandler(userService)

	// =========================================================================
	// Router & Middleware
	// =========================================================================

	r := gin.Default()

	// Use custom local CORS middleware
	r.Use(LocalCORSMiddleware())

	// Serve static files
	r.Static("/uploads", "./uploads")

	// API v1 route group
	api := r.Group("/api/v1")
	{
		// --- Public Routes ---
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/otp/request", authHandler.RequestOTP)
			auth.POST("/otp/verify", authHandler.VerifyOTP)
			auth.POST("/forgot-password", authHandler.ForgotPassword)
			auth.POST("/verify-recovery-code", authHandler.VerifyRecoveryCode)
			auth.POST("/reset-password", authHandler.ResetPassword)
		}

		api.POST("/verification/verify", identityHandler.Verify)
		api.GET("/blacklist/search", reportHandler.SearchBlacklist)

		petsPublic := api.Group("/pets")
		{
			petsPublic.GET("", petHandler.GetAll)
			petsPublic.GET("/:id", petHandler.GetPetByID)
			petsPublic.GET("/nearby", petHandler.GetNearby)
		}

		// --- Protected Routes ---
		protected := api.Group("/")
		protected.Use(middleware.AuthMiddleware())
		{
			protected.POST("/auth/switch-role", authHandler.SwitchRole)
			protected.PUT("/profile", userHandler.UpdateProfile)
			protected.GET("/profile", userHandler.GetProfile)
			protected.GET("/users/:id", userHandler.GetUserByID)
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
				match.POST("/:id/read", socialHandler.MarkAsRead)
				match.GET("/adopter", matchHandler.GetAdopterMatches)
				match.POST("/unmatch", matchHandler.Unmatch)
			}

			protected.POST("/reviews", socialHandler.CreateReview)
			protected.GET("/users/:id/reviews", socialHandler.GetUserReviews)
			protected.POST("/report", reportHandler.Create)

			// WebSocket endpoint
			protected.GET("/ws", wsHandler.HandleConnections)
		}

		// --- Admin Routes ---
		admin := protected.Group("/admin")
		admin.Use(middleware.RequireRole("admin"))
		{
			admin.GET("/reports", adminHandler.GetReports)
			admin.GET("/reports/:id", adminHandler.GetReportDetails)
			admin.POST("/reports/:id/resolve", adminHandler.Resolve)
		}

		// --- Health Check ---
		api.Any("/health", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"status":  "online",
				"message": "PAWS Backend is up and running",
			})
		})
	}

	// =========================================================================
	// Start Server
	// =========================================================================

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("PAWS server starting on port %s", port)

	if err := r.Run(":" + port); err != nil {
		log.Fatal("Fatal server error:", err)
	}
}

// LocalCORSMiddleware provides a robust CORS implementation that handles
// preflight OPTIONS requests correctly, which is crucial for deployments
// like Vercel.
func LocalCORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Allow dynamic origin
		origin := c.Request.Header.Get("Origin")
		if origin != "" {
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
		} else {
			c.Writer.Header().Set("Access-Control-Allow-Origin", "*") // Fallback
		}

		// Set allowed headers, methods, and credentials
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		// Handle preflight OPTIONS requests by aborting with a 204 status.
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

