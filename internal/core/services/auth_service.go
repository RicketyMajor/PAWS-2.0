// Package services contains the core business logic of the application.
package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
)

// registrationCache is a temporary structure to hold user data during the OTP verification process.
type registrationCache struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
	Run      string `json:"run"`
	Role     string `json:"role"`
}

// =========================================================================
// Service Definition
// =========================================================================

// ErrUnavailable marks the failure of a dependency — database, cache — rather than a
// problem with the caller's request. Handlers map it to 503 instead of 400: the request
// was well formed, the platform was not. Wrapped errors keep the cause for the log while
// letting the handler answer without leaking infrastructure detail to the client.
var ErrUnavailable = errors.New("a required service is unavailable")

// AuthService provides business logic for authentication-related operations.
type AuthService struct {
	db          *gorm.DB
	redisClient *redis.Client
}

// NewAuthService creates a new AuthService, initializing a Redis client.
func NewAuthService(dbOrNil *gorm.DB) *AuthService {
	redisURL := os.Getenv("REDIS_URL")
	var rdb *redis.Client

	if redisURL != "" {
		// Parse the full URL, including credentials and TLS if present (rediss://)
		opt, err := redis.ParseURL(redisURL)
		if err != nil {
			log.Fatalf("Error parsing REDIS_URL in AuthService: %v", err)
		}
		rdb = redis.NewClient(opt)
	} else {
		// Fallback for local development
		log.Println("REDIS_URL not detected, using localhost:6379 for Auth")
		rdb = redis.NewClient(&redis.Options{
			Addr:     "localhost:6379",
			Password: "",
			DB:       0,
		})
	}

	if dbOrNil == nil {
		return &AuthService{db: database.DB, redisClient: rdb}
	}
	return &AuthService{db: dbOrNil, redisClient: rdb}
}

// =========================================================================
// Password Management
// =========================================================================

// UpdatePassword updates a user's password, typically for the password reset flow.
func (s *AuthService) UpdatePassword(email, newPassword string) error {
	var user domain.User
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		return errors.New("user not found")
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	user.Password = string(hashedPassword)
	if err := s.db.Save(&user).Error; err != nil {
		return fmt.Errorf("error updating password: %v", err)
	}

	return nil
}

// =========================================================================
// User Registration
// =========================================================================

// InitiateRegistration validates new user data and stores it temporarily in Redis pending OTP verification.
func (s *AuthService) InitiateRegistration(name, email, password, run, role string) error {
	// 1. Check against the global blacklist by RUN.
	isBanned, err := s.CheckBlacklist(run)
	if err != nil {
		return err
	}
	if isBanned {
		return fmt.Errorf("registration denied due to blacklist status")
	}

	roleNormalized := strings.ToLower(role)
	if roleNormalized == "" {
		roleNormalized = "adopter" // Default role
	}

	// 2. Check for an existing user with the same RUN or Email for the SPECIFIC role.
	var existingUser domain.User
	err = s.db.Where("(run = ? OR email = ?) AND role = ?", run, email, roleNormalized).First(&existingUser).Error
	if err == nil {
		// If err is nil, a user was found, so it's a duplicate.
		return fmt.Errorf("an account for the role '%s' already exists with this Email or RUN", roleNormalized)
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	// 3. Store temporary registration data in Redis.
	tempData := registrationCache{
		Name:     name,
		Email:    email,
		Password: string(hashedPassword),
		Run:      run,
		Role:     roleNormalized,
	}

	userData, err := json.Marshal(tempData)
	if err != nil {
		return err
	}

	ctx := context.Background()
	key := fmt.Sprintf("pending_user:%s:%s", email, roleNormalized)
	err = s.redisClient.Set(ctx, key, userData, 10*time.Minute).Err()
	if err != nil {
		return fmt.Errorf("%w: storing temporary registration data: %v", ErrUnavailable, err)
	}

	return nil
}

// CompleteRegistration retrieves user data from Redis and creates the user in the database.
func (s *AuthService) CompleteRegistration(email string) (*domain.User, error) {
	ctx := context.Background()

	// Try to find a pending registration for either role.
	keys := []string{
		fmt.Sprintf("pending_user:%s:adopter", email),
		fmt.Sprintf("pending_user:%s:rescuer", email),
	}

	var validKey string
	var val string
	var found bool

	for _, k := range keys {
		v, err := s.redisClient.Get(ctx, k).Result()
		if err == nil {
			validKey = k
			val = v
			found = true
			break
		}
	}

	if !found {
		return nil, errors.New("no pending registration found, or it has expired")
	}

	var tempData registrationCache
	if err := json.Unmarshal([]byte(val), &tempData); err != nil {
		return nil, err
	}

	user := domain.User{
		Name:     tempData.Name,
		Email:    tempData.Email,
		Password: tempData.Password,
		Run:      tempData.Run,
		Role:     tempData.Role,
	}

	if err := s.db.Create(&user).Error; err != nil {
		return nil, fmt.Errorf("error finalizing registration: %v", err)
	}

	// Clean up the temporary key from Redis.
	s.redisClient.Del(ctx, validKey)

	return &user, nil
}

// =========================================================================
// Login & Role Switching
// =========================================================================

// Login authenticates a user and generates a JWT.
func (s *AuthService) Login(email, password string) (string, error) {
	var user domain.User
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		return "", errors.New("invalid credentials")
	}
	if user.IsBanned {
		return "", errors.New("account is suspended")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password)); err != nil {
		return "", errors.New("invalid credentials")
	}

	return s.GenerateTokenForUser(&user)
}

// SwitchRole finds the user's alternate profile (based on RUN) and generates a new token.
func (s *AuthService) SwitchRole(currentUserID uint) (string, *domain.User, error) {
	// 1. Get the current user to know their RUN and current role.
	var currentUser domain.User
	if err := s.db.First(&currentUser, currentUserID).Error; err != nil {
		return "", nil, errors.New("current user not found")
	}

	// 2. Determine the target role.
	targetRole := "rescuer"
	if currentUser.Role == "rescuer" {
		targetRole = "adopter"
	}

	// 3. Find the "twin" profile (same RUN, different role).
	var targetUser domain.User
	if err := s.db.Where("run = ? AND role = ?", currentUser.Run, targetRole).First(&targetUser).Error; err != nil {
		return "", nil, fmt.Errorf("no associated profile found for the %s role", targetRole)
	}

	// 4. Generate a new token for the target identity.
	token, err := s.GenerateTokenForUser(&targetUser)
	if err != nil {
		return "", nil, err
	}

	return token, &targetUser, nil
}

// =========================================================================
// Security & Token Generation
// =========================================================================

// CheckBlacklist checks if a given RUN is in the blacklist.
func (s *AuthService) CheckBlacklist(run string) (bool, error) {
	if strings.TrimSpace(run) == "" {
		return false, errors.New("RUN cannot be empty")
	}

	var entry domain.BlacklistEntry
	err := s.db.Where("run = ?", run).First(&entry).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return false, nil // Not found is not an error here.
		}
		return false, fmt.Errorf("%w: querying blacklist: %v", ErrUnavailable, err)
	}
	return true, nil // Entry found.
}

// GenerateTokenForUser creates a JWT for a given user.
func (s *AuthService) GenerateTokenForUser(user *domain.User) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":     user.ID,
		"user_id": user.ID,
		"role":    user.Role,
		"exp":     time.Now().Add(time.Hour * 24).Unix(),
	})
	return token.SignedString([]byte(os.Getenv("JWT_SECRET")))
}

// GenerateTokenForEmail creates a JWT for a user identified by email.
func (s *AuthService) GenerateTokenForEmail(email string) (string, error) {
	var user domain.User
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		return "", errors.New("user not found")
	}
	return s.GenerateTokenForUser(&user)
}
