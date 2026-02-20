package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"github.com/redis/go-redis/v9"
)

type EmailEvent struct {
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

type OTPService struct {
	redisClient *redis.Client
	mqClient    *messaging.RabbitMQClient
}

// --- NUEVA CONEXIÓN UNIFICADA ---
func NewOTPService(mq *messaging.RabbitMQClient) *OTPService {
	redisURL := os.Getenv("REDIS_URL")
	var rdb *redis.Client

	if redisURL != "" {
		opt, err := redis.ParseURL(redisURL)
		if err != nil {
			log.Fatalf("Error parseando REDIS_URL en OTPService: %v", err)
		}
		rdb = redis.NewClient(opt)
	} else {
		// Fallback para desarrollo local
		log.Println("REDIS_URL no detectada, usando localhost:6379 para OTP")
		rdb = redis.NewClient(&redis.Options{
			Addr:     "localhost:6379",
			Password: "",
			DB:       0,
		})
	}

	return &OTPService{
		redisClient: rdb,
		mqClient:    mq,
	}
}

// GenerateOTP: Para Registro (Genérico)
func (s *OTPService) GenerateOTP(email string) (string, error) {
	return s.sendOTP(email, "Tu código de verificación PAWS", "Hola, tu código de verificación es: %s")
}

// --- NUEVO: OTP para Recuperación de Contraseña ---
func (s *OTPService) GenerateRecoveryOTP(email string) (string, error) {
	return s.sendOTP(email, "Recuperación de Contraseña - PAWS", "Hola, hemos recibido una solicitud para restablecer tu contraseña.\n\nTu código de recuperación es: %s\n\nSi no fuiste tú, ignora este correo.")
}

// Función auxiliar privada para no repetir lógica
func (s *OTPService) sendOTP(email, subject, bodyTemplate string) (string, error) {
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	code := fmt.Sprintf("%06d", rng.Intn(1000000))

	// Guardar en Redis (5 min)
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)
	err := s.redisClient.Set(ctx, key, code, 5*time.Minute).Err()
	if err != nil {
		return "", fmt.Errorf("error guardando OTP en Redis: %v", err)
	}

	// Crear evento de correo
	event := EmailEvent{
		To:      email,
		Subject: subject,
		Body:    fmt.Sprintf(bodyTemplate, code),
	}

	eventBytes, _ := json.Marshal(event)

	if s.mqClient != nil {
		err = s.mqClient.Publish("email_notifications", eventBytes)
		if err != nil {
			log.Printf("Error RabbitMQ: %v. Log: %s -> %s", err, email, code)
		}
	} else {
		log.Printf("[DEV EMAIL] Para: %s | Asunto: %s | Código: %s", email, subject, code)
	}

	return code, nil
}

func (s *OTPService) VerifyOTP(email, inputCode string) bool {
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)

	val, err := s.redisClient.Get(ctx, key).Result()
	if err == redis.Nil || err != nil {
		return false
	}

	if val == inputCode {
		s.redisClient.Del(ctx, key) // Borrar tras uso exitoso
		return true
	}
	return false
}
