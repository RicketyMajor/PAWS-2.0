// Package services contains the core business logic of the application.
package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/email"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"github.com/redis/go-redis/v9"
)

// EmailEvent defines the structure for an email to be sent via the message queue.
type EmailEvent struct {
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

// =========================================================================
// Service Definition
// =========================================================================

// OTPService handles the generation, verification, and delivery of one-time passwords.
type OTPService struct {
	redisClient *redis.Client
	mqClient    *messaging.RabbitMQClient
	emailClient *email.EmailClient
}

// NewOTPService creates a new OTPService, initializing connections to Redis and RabbitMQ.
func NewOTPService(mq *messaging.RabbitMQClient, ec *email.EmailClient) *OTPService {
	redisURL := os.Getenv("REDIS_URL")
	var rdb *redis.Client

	if redisURL != "" {
		opt, err := redis.ParseURL(redisURL)
		if err != nil {
			log.Fatalf("Error parsing REDIS_URL in OTPService: %v", err)
		}
		rdb = redis.NewClient(opt)
	} else {
		// Fallback for local development
		log.Println("REDIS_URL not detected, using localhost:6379 for OTP")
		rdb = redis.NewClient(&redis.Options{
			Addr:     "localhost:6379",
			Password: "",
			DB:       0,
		})
	}

	return &OTPService{
		redisClient: rdb,
		mqClient:    mq,
		emailClient: ec,
	}
}

// =========================================================================
// Service Methods
// =========================================================================

// GenerateOTP creates and sends a generic OTP for registration.
func (s *OTPService) GenerateOTP(email string) (string, error) {
	return s.sendOTP(email, "Your PAWS Verification Code", "Hello, your verification code is: %s")
}

// GenerateRecoveryOTP creates and sends an OTP specifically for password recovery.
func (s *OTPService) GenerateRecoveryOTP(email string) (string, error) {
	return s.sendOTP(email, "PAWS Password Recovery", "Hello, we received a request to reset your password.\n\nYour recovery code is: %s\n\nIf you did not make this request, please ignore this email.")
}

// VerifyOTP checks if the provided code for a given email is valid.
func (s *OTPService) VerifyOTP(email, inputCode string) bool {
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)

	val, err := s.redisClient.Get(ctx, key).Result()
	if err == redis.Nil || err != nil {
		return false
	}

	if val == inputCode {
		s.redisClient.Del(ctx, key) // Delete the OTP after successful use.
		return true
	}
	return false
}

// =========================================================================
// Helper Functions
// =========================================================================

// sendOTP is a private helper that handles OTP generation, storage in Redis, and queuing the email.
func (s *OTPService) sendOTP(email, subject, bodyTemplate string) (string, error) {
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	code := fmt.Sprintf("%06d", rng.Intn(1000000))

	// Store the OTP in Redis with a 5-minute expiration.
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)
	err := s.redisClient.Set(ctx, key, code, 5*time.Minute).Err()
	if err != nil {
		return "", fmt.Errorf("error saving OTP to Redis: %v", err)
	}

	// Create and queue the email event.
	event := EmailEvent{
		To:      email,
		Subject: subject,
		Body:    fmt.Sprintf(bodyTemplate, code),
	}
	eventBytes, _ := json.Marshal(event)

	if s.mqClient != nil {
		err = s.mqClient.Publish("email_notifications", eventBytes)
		if err != nil {
			// Log error but don't fail the operation, as the code is still valid.
			log.Printf("RabbitMQ publishing error: %v. Log: %s -> %s", err, email, code)
		}
	} else {
		// If RabbitMQ is disabled, try to send synchronously
		if s.emailClient != nil {
			log.Printf("RabbitMQ disabled, enviando correo síncrono a %s", email)
			err = s.emailClient.Send(email, subject, fmt.Sprintf(bodyTemplate, code))
			if err != nil {
				log.Printf("Error enviando correo síncrono: %v", err)
			}
		} else {
			log.Printf("[DEV EMAIL] To: %s | Subject: %s | Code: %s", email, subject, code)
		}
	}

	return code, nil
}
