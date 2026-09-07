// Package services contains the core business logic of the application.
package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/email"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"github.com/redis/go-redis/v9"
)

// otpCooldown is how long an address must wait between codes. It is the only limit
// an attacker cannot sidestep by changing IP, because it is keyed by the mailbox
// being flooded rather than by whoever asked.
const otpCooldown = time.Minute

// ErrOTPThrottled means a code went to this address moments ago. It is the caller
// going too fast, not a fault on our side, so handlers answer 429 and not 500.
var ErrOTPThrottled = errors.New("a code was already sent to this address recently")

// dailyMailBudget caps how much of the provider's 300/day allowance this service will
// spend. Per-IP limits cannot protect a shared quota — enough addresses spread the
// load until it drains anyway — so this is the only ceiling that always holds. The
// headroom below 300 leaves room to send by hand while diagnosing.
const dailyMailBudget = 250

// ErrMailBudgetExhausted means the service, not the caller, is out of capacity for
// today. Handlers answer 503: it is temporary and it is ours.
var ErrMailBudgetExhausted = errors.New("the daily mail budget is spent")

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
// ec is required and must not be nil; it is the only delivery path when mq is absent.
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
	ctx := context.Background()

	// Claim the cooldown before minting anything. Checking later would let a throttled
	// request overwrite the code the user already received, locking out the very person
	// being flooded. SetNX is the claim and the check in one round trip.
	fresh, err := s.redisClient.SetNX(ctx, fmt.Sprintf("otp:cooldown:%s", email), 1, otpCooldown).Result()
	if err != nil {
		return "", fmt.Errorf("%w: checking OTP cooldown: %v", ErrUnavailable, err)
	}
	if !fresh {
		return "", ErrOTPThrottled
	}

	// Spend from today's budget only once the cooldown has agreed this send is real.
	// Counting first would let a flood aimed at one address drain the allowance for
	// everybody while not sending a single message.
	budgetKey := "otp:budget:" + time.Now().UTC().Format("2006-01-02")
	spent, err := s.redisClient.Incr(ctx, budgetKey).Result()
	if err != nil {
		return "", fmt.Errorf("%w: counting the mail budget: %v", ErrUnavailable, err)
	}
	if spent == 1 {
		// The key is named after its day, so a failed Expire leaves a harmless leftover
		// rather than a budget that never resets. Tomorrow counts under a new name.
		s.redisClient.Expire(ctx, budgetKey, 25*time.Hour)
	}
	if spent > dailyMailBudget {
		// Nothing else records this. Without the line, the day the allowance runs out
		// looks exactly like the mail provider being broken.
		log.Printf("mail budget exhausted: %d sends attempted today, cap is %d", spent, dailyMailBudget)
		return "", ErrMailBudgetExhausted
	}

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	code := fmt.Sprintf("%06d", rng.Intn(1000000))

	// Store the OTP in Redis with a 5-minute expiration.
	key := fmt.Sprintf("otp:%s", email)
	if err = s.redisClient.Set(ctx, key, code, 5*time.Minute).Err(); err != nil {
		return "", fmt.Errorf("error saving OTP to Redis: %v", err)
	}

	// Create and queue the email event.
	event := EmailEvent{
		To:      email,
		Subject: subject,
		Body:    fmt.Sprintf(bodyTemplate, code),
	}
	eventBytes, _ := json.Marshal(event)

	// A delivery failure must reach the caller. Handlers already turn this into a 500,
	// but they only ever saw nil, so a blocked send still answered "code sent" and the
	// user waited for mail that was never dispatched.
	if s.mqClient != nil {
		if err = s.mqClient.Publish("email_notifications", eventBytes); err != nil {
			return "", fmt.Errorf("no se pudo encolar el correo de verificación: %w", err)
		}
	} else if err = s.emailClient.Send(email, subject, fmt.Sprintf(bodyTemplate, code)); err != nil {
		return "", fmt.Errorf("no se pudo enviar el correo de verificación: %w", err)
	}

	return code, nil
}
