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

func NewOTPService(mq *messaging.RabbitMQClient) *OTPService {
	// 1. Leemos configuración del entorno (Soporte Híbrido Local/K8s)
	redisHost := os.Getenv("REDIS_HOST")
	redisPort := os.Getenv("REDIS_PORT")
	
	// Fallback por si faltan variables
	if redisHost == "" { redisHost = "localhost" }
	if redisPort == "" { redisPort = "6379" }

	addr := fmt.Sprintf("%s:%s", redisHost, redisPort)

	// 2. Conexión a Redis
	rdb := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: "", // Si tienes pass, agrégalo a las variables de entorno
		DB:       0,
	})

	return &OTPService{
		redisClient: rdb,
		mqClient:    mq,
	}
}

func (s *OTPService) GenerateOTP(email string) (string, error) {
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	code := fmt.Sprintf("%06d", rng.Intn(1000000))

	// Guardar OTP en Redis (TTL 5 min)
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)
	err := s.redisClient.Set(ctx, key, code, 5*time.Minute).Err()
	if err != nil {
		return "", fmt.Errorf("error guardando OTP en Redis: %v", err)
	}

	// Crear evento de correo
	event := EmailEvent{
		To:      email,
		Subject: "Tu código de verificación PAWS",
		Body:    fmt.Sprintf("Hola, tu código de verificación es: %s. \n\nEste código expirará en 5 minutos.", code),
	}

	eventBytes, _ := json.Marshal(event)

	// Enviar a RabbitMQ (si existe) o Fallback a Log
	if s.mqClient != nil {
		err = s.mqClient.Publish("email_notifications", eventBytes)
		if err != nil {
			log.Printf("Error RabbitMQ: %v. Usando Log.", err)
			log.Printf("[FALLBACK EMAIL] Para: %s | Código: %s", email, code)
		} else {
			log.Printf("Evento de email enviado a RabbitMQ para: %s", email)
		}
	} else {
		log.Printf("[DEV EMAIL] Para: %s | Código: %s", email, code)
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
		// Borramos el OTP para que no se pueda usar dos veces
		s.redisClient.Del(ctx, key)
		return true
	}
	return false
}