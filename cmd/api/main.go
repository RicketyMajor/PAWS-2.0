package main

import (
	"log"
	"os"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
	
	// Unificamos el import del transporte HTTP para evitar confusión
	httpTransport "github.com/RicketyMajor/PAWS-2.0/internal/transport/http"
	"github.com/RicketyMajor/PAWS-2.0/internal/transport/http/middleware"
	
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// 1. Configuración inicial
	if err := godotenv.Load(); err != nil {
		log.Println("No se encontró archivo .env, usando variables de entorno del sistema")
	}

	database.Connect()
	// Migramos todas las tablas necesarias
	if err := database.DB.AutoMigrate(
		&domain.User{}, 
		&domain.BlacklistEntry{}, 
		&domain.Report{},
		&domain.UserProfile{}, // <--- NUEVO
		&domain.Pet{},         // <--- ACTUALIZADO
		&domain.Match{},
		&domain.Message{}, 
		&domain.Review{},       // <--- NUEVO
	); err != nil {
    		log.Fatal("Error migrando la base de datos:", err)
	}
	// 2. Inyección de Dependencias (ORDEN CORREGIDO)
	
	// A. Primero: Servicios Base (No dependen de otros servicios)
	// Servicios Base
	otpService := services.NewOTPService() // <--- NUEVO: Inicializar Redis/OTP
	authService := services.NewAuthService(nil) // Creamos este PRIMERO
	petService := services.NewPetService()
	fileService := services.NewFileService()
	identityService := services.NewIdentityService()
	chatService := services.NewChatService(database.DB)
	reviewService := services.NewReviewService(database.DB)
	// NUEVO: User Service
	userService := services.NewUserService(database.DB)
	hub := httpTransport.NewHub()
	go hub.Run()

	// B. Segundo: Servicios Dependientes (Usan los servicios base)
	// Ahora sí podemos pasarle 'authService' porque ya existe
	reportService := services.NewReportService(database.DB, authService) 
	// ACTUALIZADO: Match Service ahora pide DB y PetService
	matchService := services.NewMatchService(database.DB, petService)

	// C. Tercero: Handlers
	authHandler := httpTransport.NewAuthHandler(authService, otpService)
	petHandler := httpTransport.NewPetHandler(petService)
	uploadHandler := httpTransport.NewUploadHandler(fileService)
	identityHandler := httpTransport.NewIdentityHandler(identityService)
	matchHandler := httpTransport.NewMatchHandler(matchService)
	// HANDLER WEBSOCKET (ACTUALIZADO)
	// Antes: wsHandler := httpTransport.NewWSHandler(hub)
	// Ahora: Pasamos también chatService
	wsHandler := httpTransport.NewWSHandler(hub, chatService)
	reportHandler := httpTransport.NewReportHandler(reportService)
	// NUEVO: User Handler
	userHandler := httpTransport.NewUserHandler(userService, matchService)
	socialHandler := httpTransport.NewSocialHandler(chatService, reviewService)

	// 3. Configurar Router (Gin)
	r := gin.Default()
	r.Static("/uploads", "./uploads") // Servir imágenes estáticas

	api := r.Group("/api/v1")
	{
		// --- RUTAS PÚBLICAS ---
		
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/otp/request", authHandler.RequestOTP)
			auth.POST("/otp/verify", authHandler.VerifyOTP)
			
		}

		petsPublic := api.Group("/pets")
		{
			petsPublic.GET("/search", petHandler.Search)
			petsPublic.GET("", petHandler.GetAll)
		}
		
		// Verificación de Identidad (Público para el registro)
		verification := api.Group("/verification")
		{
			verification.POST("/verify", identityHandler.Verify)
		}

		// --- RUTAS PROTEGIDAS (Requieren Token) ---
		
		// Grupo general protegido
		protected := api.Group("/")
		protected.Use(middleware.AuthMiddleware()) // <--- IMPORTANTE: Descomentado para que funcione
		{
			// Reportes: Necesitamos saber QUIÉN reporta (userID del token)
			protected.POST("/report", reportHandler.Create)
			
			// Chat
			protected.GET("/chat/ws", wsHandler.HandleConnections)
			
			// Subida de archivos
			protected.POST("/files/upload", uploadHandler.Upload)

			// Match (GET)
			protected.GET("/pets/match", matchHandler.GetMatches)
			// Perfil de Usuario
			protected.PUT("/profile", userHandler.UpdateProfile)

			// Matchmaking
			protected.GET("/matches/candidates", userHandler.GetSwipeDeck) // Ya existía
			
			// NUEVAS RUTAS
			protected.POST("/matches/swipe", matchHandler.Swipe)        // Adoptante da Like
			protected.GET("/matches/requests", matchHandler.GetPending) // Rescatista ve Likes
			protected.POST("/matches/respond", matchHandler.Respond)    // Rescatista acepta/rechaza
			// CHAT HISTORY
			protected.GET("/matches/:id/messages", socialHandler.GetChatHistory)

			// REVIEWS
			protected.POST("/reviews", socialHandler.CreateReview)
			// WEBSOCKET (¡Ponlo aquí!)
			protected.GET("/ws", wsHandler.HandleConnections)
		}

		// Mascotas (Escritura)
		petsProtected := api.Group("/pets")
		petsProtected.Use(middleware.AuthMiddleware())
		{
			petsProtected.POST("", petHandler.Create)
		}
	}

	// 4. Arrancar Servidor
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Servidor PAWS corriendo en puerto %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatal("Error al iniciar el servidor:", err)
	}
}