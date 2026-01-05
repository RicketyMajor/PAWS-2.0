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
	// --- AGREGAR ESTO TEMPORALMENTE ---
    url := os.Getenv("DATABASE_URL")
    if url != "" {
        log.Println("DEBUG: ¡Variable DATABASE_URL encontrada! Longitud:", len(url))
        // No imprimas la URL completa por seguridad, solo verifica que existe.
    } else {
        log.Println("DEBUG: DATABASE_URL está vacía. Godotenv cargó el archivo pero no leyó la variable.")
    }
    // ----------------------------------

	database.Connect()

    // ZONA DE PELIGRO: LIMPIEZA PARA TESTEO 
    // Descomenta estas líneas para borrar TODOS los usuarios y empezar de cero.
    // Vuélvelas a comentar cuando quieras persistencia.
    
    //database.DB.Migrator().DropTable(&domain.User{})         // Borra usuarios
    //database.DB.Exec("DELETE FROM blacklist_entries")        // Borra blacklist (opcional)
    //database.DB.Exec("DELETE FROM otps")                     // (Si tuvieras tabla de OTPs)
    
    // Nota: Si borras User, se borrarán en cascada perfiles, mascotas, etc.
    
	//database.DB.Migrator().DropTable(&domain.Report{}) // Esta ya la tenías

	// Migraciones (Esto volverá a crear la tabla vacía inmediatamente después)
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
	// KILL SWITCH: RabbitMQ & Async (Etapa 10)
	// -------------------------------------------------------------------------
	var mqClient *messaging.RabbitMQClient
	var err error
	
	// 1. Leemos configuración de RabbitMQ del entorno
	// Si estamos en local (go run), usaremos localhost. En K8s, usaremos el servicio.
	rabbitUser := os.Getenv("RABBITMQ_USER")
	rabbitPass := os.Getenv("RABBITMQ_PASSWORD")
	rabbitHost := os.Getenv("RABBITMQ_HOST")
	rabbitPort := os.Getenv("RABBITMQ_PORT")

	// Valores por defecto (Para K8s o Local standard)
	if rabbitUser == "" { rabbitUser = "guest" }
	if rabbitPass == "" { rabbitPass = "guest" }
	if rabbitHost == "" { rabbitHost = "localhost" } // <--- CAMBIO CLAVE: Default a localhost
	if rabbitPort == "" { rabbitPort = "5672" }

	rabbitURL := fmt.Sprintf("amqp://%s:%s@%s:%s/", rabbitUser, rabbitPass, rabbitHost, rabbitPort)

	// 2. Intentamos conectar si está habilitado
	if os.Getenv("ENABLE_ASYNC_FEATURES") == "true" {
		log.Printf("Intentando conectar a RabbitMQ en: %s:%s...", rabbitHost, rabbitPort)
		mqClient, err = messaging.ConnectRabbitMQ(rabbitURL)
		if err != nil {
			log.Printf("RabbitMQ error: %v. \nEl sistema funcionará en MODO SÍNCRONO (Terminal).", err)
		} else {
			defer mqClient.Close()
			log.Println("Conectado a RabbitMQ (Sistema de Correos Activo)")
		}
	} else {
		log.Println("ℹAsync Features desactivadas. Usando modo síncrono simple (Logs en Terminal).")
	}

	emailClient := email.NewEmailClient()

	// Worker solo arranca si hay conexión real
	if mqClient != nil {
		workers.StartEmailConsumer(mqClient, emailClient)
		workers.StartNotificationConsumer(mqClient, database.DB)
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
	matchService := services.NewMatchService(database.DB, petService, mqClient)

	// WebSocket Hub
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
			protected.POST("/notifications/token", notificationHandler.UpdateToken)

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