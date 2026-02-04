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
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
	"github.com/golang-jwt/jwt/v5"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
)

// Estructura auxiliar para registro temporal
type registrationCache struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Password string `json:"password"`
	Run      string `json:"run"`
	Role     string `json:"role"`
}

type AuthService struct {
	db          *gorm.DB
	redisClient *redis.Client
}

func NewAuthService(dbOrNil *gorm.DB) *AuthService {
	redisHost := os.Getenv("REDIS_HOST")
	redisPort := os.Getenv("REDIS_PORT")
	redisPass := os.Getenv("REDIS_PASSWORD") // <--- NUEVO: Leemos la contraseña

	if redisHost == "" { redisHost = "localhost" }
	if redisPort == "" { redisPort = "6379" }
	
	rdb := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", redisHost, redisPort),
		Password: redisPass, // <--- NUEVO: La usamos aquí
		DB:       0,
	})

	if dbOrNil == nil {
		return &AuthService{db: database.DB, redisClient: rdb}
	}
	return &AuthService{db: dbOrNil, redisClient: rdb}
}

// UpdatePassword (Reset Password Flow)
func (s *AuthService) UpdatePassword(email, newPassword string) error {
	var user domain.User
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		return errors.New("usuario no encontrado")
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	user.Password = string(hashedPassword)
	if err := s.db.Save(&user).Error; err != nil {
		return fmt.Errorf("error actualizando contraseña: %v", err)
	}

	return nil
}

// InitiateRegistration: Verifica duplicidad por ROL y guarda en Redis
func (s *AuthService) InitiateRegistration(name, email, password, run, role string) error {
	// 1. Verificar Blacklist Global (por RUT)
	isBanned, err := s.CheckBlacklist(run)
	if err != nil { return err }
	if isBanned { return fmt.Errorf("registro denegado (Evil PAWS)") }

	roleNormalized := strings.ToLower(role)
	if roleNormalized == "" { roleNormalized = "adopter" }

	// 2. CAMBIO DE LÓGICA: Verificar existencia ESPECÍFICA para este Rol.
	// Buscamos si ya existe alguien con este (RUT o Email) Y que tenga el MISMO ROL.
	var existingUser domain.User
	err = s.db.Where("(run = ? OR email = ?) AND role = ?", run, email, roleNormalized).First(&existingUser).Error

	if err == nil {
		// Si err es nil, SIGNIFICA QUE LO ENCONTRÓ -> DUPLICADO
		return fmt.Errorf("ya existe una cuenta de %s registrada con este Email o RUT", roleNormalized)
	}
	// Si no lo encuentra (error RecordNotFound), procedemos.

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil { return err }

	tempData := registrationCache{
		Name:     name,
		Email:    email,
		Password: string(hashedPassword),
		Run:      run,
		Role:     roleNormalized,
	}

	userData, err := json.Marshal(tempData)
	if err != nil { return err }

	ctx := context.Background()
	key := fmt.Sprintf("pending_user:%s:%s", email, roleNormalized)
	
	err = s.redisClient.Set(ctx, key, userData, 10*time.Minute).Err()
	if err != nil {
		return fmt.Errorf("error guardando registro temporal: %v", err)
	}

	return nil
}

// CompleteRegistration: Recupera de Redis y guarda en Postgres
func (s *AuthService) CompleteRegistration(email string) (*domain.User, error) {
	ctx := context.Background()
	
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
		return nil, errors.New("no hay registro pendiente o expiró")
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
		return nil, fmt.Errorf("error finalizando registro: %v", err)
	}

	s.redisClient.Del(ctx, validKey)

	return &user, nil
}

func (s *AuthService) Login(email, password string) (string, error) {
	// Fase 1: Login simple (toma el primero que encuentra)
	// Fase 2: Podríamos mejorar esto si queremos que Login devuelva ambos perfiles,
	// pero por ahora SwitchRole manejará el cambio.
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

// SwitchRole: Busca la "otra" cuenta del usuario basada en su RUT y genera un nuevo token.
func (s *AuthService) SwitchRole(currentUserID uint) (string, *domain.User, error) {
	// 1. Obtener usuario actual para saber su RUT y Rol actual
	var currentUser domain.User
	if err := s.db.First(&currentUser, currentUserID).Error; err != nil {
		return "", nil, errors.New("usuario actual no encontrado")
	}

	// 2. Determinar el rol objetivo
	targetRole := "rescuer"
	if currentUser.Role == "rescuer" {
		targetRole = "adopter"
	}

	// 3. Buscar el "gemelo" (mismo RUT, rol objetivo)
	var targetUser domain.User
	if err := s.db.Where("run = ? AND role = ?", currentUser.Run, targetRole).First(&targetUser).Error; err != nil {
		// Si no lo encuentra, significa que el usuario aún no ha creado el otro perfil
		return "", nil, errors.New("no existe un perfil asociado para el modo " + targetRole)
	}

	// 4. Generar Token para la nueva identidad
	token, err := s.GenerateTokenForUser(&targetUser)
	if err != nil {
		return "", nil, err
	}

	return token, &targetUser, nil
}

func (s *AuthService) CheckBlacklist(run string) (bool, error) {
	var entry domain.BlacklistEntry
	if err := s.db.Where("run = ?", run).First(&entry).Error; err != nil {
		if err == gorm.ErrRecordNotFound { return false, nil }
		return false, err
	}
	return true, nil
}

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

func (s *AuthService) GenerateTokenForEmail(email string) (string, error) {
	var user domain.User
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		return "", errors.New("usuario no encontrado")
	}
	return s.GenerateTokenForUser(&user)
}