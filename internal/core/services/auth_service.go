package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"gorm.io/gorm"
	"github.com/redis/go-redis/v9" // Necesitamos Redis aquí también
	"golang.org/x/crypto/bcrypt"
	"github.com/golang-jwt/jwt/v5"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
)

// --- AGREGAR ESTA ESTRUCTURA AL INICIO ---
// Usamos esta estructura auxiliar para asegurarnos de que la contraseña
// SÍ se guarde en Redis, independientemente de las etiquetas JSON de domain.User
type registrationCache struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"` // Aquí forzamos que se guarde
	Run      string `json:"run"`
	Role     string `json:"role"`
}

type AuthService struct {
	db          *gorm.DB
	redisClient *redis.Client
}

func NewAuthService(dbOrNil *gorm.DB) *AuthService {
	// 1. Configurar conexión a Redis
	redisHost := os.Getenv("REDIS_HOST")
	redisPort := os.Getenv("REDIS_PORT")
	if redisHost == "" { redisHost = "localhost" }
	if redisPort == "" { redisPort = "6379" }
	
	rdb := redis.NewClient(&redis.Options{
		Addr: fmt.Sprintf("%s:%s", redisHost, redisPort),
	})

	if dbOrNil == nil {
		return &AuthService{db: database.DB, redisClient: rdb}
	}
	return &AuthService{db: dbOrNil, redisClient: rdb}
}

// InitiateRegistration: Guarda datos en Redis usando registrationCache
func (s *AuthService) InitiateRegistration(name, email, password, run, role string) error {
	isBanned, err := s.CheckBlacklist(run)
	if err != nil { return err }
	if isBanned { return fmt.Errorf("registro denegado (Evil PAWS)") }

	var existingUser domain.User
	if s.db.Where("run = ? OR email = ?", run, email).First(&existingUser).Error == nil {
		return fmt.Errorf("ya existe una cuenta con este RUN o Email")
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil { return err }

	roleNormalized := strings.ToLower(role)
	if roleNormalized == "" { roleNormalized = "adopter" }

	// --- CAMBIO AQUÍ: Usamos la estructura cache en lugar de domain.User ---
	tempData := registrationCache{
		Name:     name,
		Email:    email,
		Password: string(hashedPassword), // Guardamos el Hash explícitamente
		Run:      run,
		Role:     roleNormalized,
	}

	userData, err := json.Marshal(tempData)
	if err != nil { return err }

	ctx := context.Background()
	key := fmt.Sprintf("pending_user:%s", email)
	
	err = s.redisClient.Set(ctx, key, userData, 10*time.Minute).Err()
	if err != nil {
		return fmt.Errorf("error guardando registro temporal: %v", err)
	}

	return nil
}

// CompleteRegistration: Recupera de Redis y guarda en Postgres
func (s *AuthService) CompleteRegistration(email string) (*domain.User, error) {
	ctx := context.Background()
	key := fmt.Sprintf("pending_user:%s", email)

	val, err := s.redisClient.Get(ctx, key).Result()
	if err == redis.Nil {
		return nil, errors.New("no hay registro pendiente o expiró")
	} else if err != nil {
		return nil, err
	}

	// --- CAMBIO AQUÍ: Deserializamos en la estructura cache ---
	var tempData registrationCache
	if err := json.Unmarshal([]byte(val), &tempData); err != nil {
		return nil, err
	}

	// Convertimos la cache al modelo de dominio real
	user := domain.User{
		Name:     tempData.Name,
		Email:    tempData.Email,
		Password: tempData.Password, // ¡Ahora sí viene el password!
		Run:      tempData.Run,
		Role:     tempData.Role,
	}

	if err := s.db.Create(&user).Error; err != nil {
		return nil, fmt.Errorf("error finalizando registro: %v", err)
	}

	s.redisClient.Del(ctx, key)

	return &user, nil
}

// --- Métodos Login, CheckBlacklist, etc. se mantienen igual ---
func (s *AuthService) Login(email, password string) (string, error) {
	var user domain.User
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		return "", errors.New("credenciales inválidas")
	}
	if user.IsBanned { return "", errors.New("cuenta suspendida") }

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password)); err != nil {
		return "", errors.New("credenciales inválidas")
	}

	return s.GenerateTokenForUser(&user)
}

func (s *AuthService) CheckBlacklist(run string) (bool, error) {
	var entry domain.BlacklistEntry
	if err := s.db.Where("run = ?", run).First(&entry).Error; err != nil {
		if err == gorm.ErrRecordNotFound { return false, nil }
		return false, err
	}
	return true, nil
}

// Helper para generar token desde Objeto User
func (s *AuthService) GenerateTokenForUser(user *domain.User) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":     user.ID,
		"user_id": user.ID,
		"role":    user.Role,
		"exp":     time.Now().Add(time.Hour * 24).Unix(),
	})
	secret := os.Getenv("JWT_SECRET")
	if secret == "" { secret = "secreto_default" }
	return token.SignedString([]byte(secret))
}

// Mantener por compatibilidad si se usa en otros lados, 
// pero ahora VerifyOTP usará CompleteRegistration preferentemente.
func (s *AuthService) GenerateTokenForEmail(email string) (string, error) {
	var user domain.User
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		return "", errors.New("usuario no encontrado")
	}
	return s.GenerateTokenForUser(&user)
}