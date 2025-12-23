package services

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"time"
	"log"

	"github.com/redis/go-redis/v9"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging" // Importar
)

// Estructura del evento que viajará por RabbitMQ
type EmailEvent struct {
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

type OTPService struct {
	redisClient *redis.Client
	mqClient    *messaging.RabbitMQClient // <--- NUEVO
}

// Actualizar Constructor
func NewOTPService(mq *messaging.RabbitMQClient) *OTPService {
	// Configuración Redis (se mantiene igual)
	rdb := redis.NewClient(&redis.Options{
		Addr:     "redis-service:6379",
		Password: "",
		DB:       0,
	})

	return &OTPService{
		redisClient: rdb,
		mqClient:    mq, // <--- Inyectar
	}
}

func (s *OTPService) GenerateOTP(email string) (string, error) {
	// 1. Generar código (Igual que antes)
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	code := fmt.Sprintf("%06d", rng.Intn(1000000))

	// 2. Guardar en Redis (Igual que antes)
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)
	err := s.redisClient.Set(ctx, key, code, 5*time.Minute).Err()
	if err != nil {
		return "", fmt.Errorf("error guardando OTP en Redis: %v", err)
	}

	// 3. EN LUGAR DE LOGUEAR -> PUBLICAR EVENTO (Async)
	event := EmailEvent{
		To:      email,
		Subject: "Tu código de verificación PAWS",
		Body:    fmt.Sprintf("Hola, tu código es: %s. Válido por 5 minutos.", code),
	}

	eventBytes, _ := json.Marshal(event)

	// Publicar a la cola "email_notifications"
	if s.mqClient != nil {
		err = s.mqClient.Publish("email_notifications", eventBytes)
		if err != nil {
			log.Printf("Error publicando evento RabbitMQ: %v", err)
			// Fallback: loguear en consola si falla la cola
			log.Printf("[FALLBACK] Para: %s | Código: %s", email, code)
		} else {
			log.Printf("Evento enviado a RabbitMQ para: %s", email)
		}
	} else {
		// Modo desarrollo sin RabbitMQ
		log.Printf("[DEV] Para: %s | Código: %s", email, code)
	}

	return code, nil
}

// VerifyOTP se mantiene igual...
func (s *OTPService) VerifyOTP(email, inputCode string) bool {
    // ... (copiar código anterior o dejar intacto)
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)
	val, err := s.redisClient.Get(ctx, key).Result()
	if err == redis.Nil || err != nil {
		return false
	}
	if val == inputCode {
		s.redisClient.Del(ctx, key)
		return true
	}
	return false
}