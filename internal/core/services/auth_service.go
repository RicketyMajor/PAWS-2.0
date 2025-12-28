package services

import (
	"errors"
	"fmt"
	"os"
	"strings" // <--- AGREGADO: Para normalizar roles
	"time"

	"gorm.io/gorm"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// AuthService agrupa la lógica de registro y login
type AuthService struct {
	db *gorm.DB
}

func NewAuthService(dbOrNil *gorm.DB) *AuthService {
	if dbOrNil == nil {
		return &AuthService{db: database.DB}
	}
	return &AuthService{db: dbOrNil}
}

// Register crea un nuevo usuario y LO RETORNA para poder usar su ID en el OTP
// CAMBIO IMPORTANTE: Ahora retorna (*domain.User, error)
func (s *AuthService) Register(name, email, password, run, role string) (*domain.User, error) {
	// 1. SEGURIDAD: Verificar si está en la Blacklist (R-SEC-03)
	isBanned, err := s.CheckBlacklist(run)
	if err != nil {
		return nil, fmt.Errorf("error verificando antecedentes: %v", err)
	}
	if isBanned {
		return nil, fmt.Errorf("registro denegado por políticas de seguridad (Evil PAWS)")
	}

	// 2. SEGURIDAD: Verificar Multicuentas (R-SEC-02)
	var existingUser domain.User
	// Usamos s.db en lugar de database.DB directo
	result := s.db.Where("run = ? OR email = ?", run, email).First(&existingUser)
	if result.Error == nil {
		return nil, fmt.Errorf("ya existe una cuenta asociada al RUN %s o al correo %s", run, email)
	}

	// 3. Hash Password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	// 4. Preparar Usuario
	// Normalizamos el rol a minúsculas para evitar problemas (ej: "Adopter" vs "adopter")
	roleNormalized := strings.ToLower(role)
	if roleNormalized == "" {
		roleNormalized = "adopter"
	}

	user := domain.User{
		Name:     name,
		Email:    email,
		Password: string(hashedPassword),
		Run:      run,
		Role:     roleNormalized,
	}

	// 5. Guardar en Base de Datos
	if err := s.db.Create(&user).Error; err != nil {
		return nil, err
	}

	// 6. RETORNAR EL USUARIO (Esto arregla el error de compilación del handler)
	return &user, nil
}

func (s *AuthService) Login(email, password string) (string, error) {
	var user domain.User

	// 1. Buscar usuario
	result := s.db.Where("email = ?", email).First(&user)
	if result.Error != nil {
		return "", errors.New("credenciales inválidas")
	}

	// 2. Verificar si está Baneado (R-SEC-03)
	if user.IsBanned {
		return "", errors.New("tu cuenta ha sido suspendida por violar las normas de seguridad")
	}

	// 3. Verificar Contraseña
	err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password))
	if err != nil {
		return "", errors.New("credenciales inválidas")
	}

	// 4. Generar JWT (MANTUVIMOS TU LÓGICA ORIGINAL AQUÍ)
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":     user.ID,   // ID del usuario
		"user_id": user.ID,   // A veces útil tenerlo explícito
		"role":    user.Role, // Rol
		"exp":     time.Now().Add(time.Hour * 24).Unix(), // 24 horas
	})

	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "secreto_super_seguro_cambiar_en_produccion"
	}

	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", err
	}

	return tokenString, nil
}

// CheckBlacklist se mantiene igual
func (s *AuthService) CheckBlacklist(run string) (bool, error) {
	if run == "" {
		return false, fmt.Errorf("el RUN no puede estar vacío")
	}

	var entry domain.BlacklistEntry
	result := s.db.Where("run = ?", run).First(&entry)

	if result.Error != nil {
		if result.Error == gorm.ErrRecordNotFound {
			return false, nil
		}
		return false, result.Error
	}

	return true, nil
}

// GenerateTokenForEmail busca un usuario y genera su token (Usado tras OTP)
func (s *AuthService) GenerateTokenForEmail(email string) (string, error) {
	var user domain.User

	// 1. Buscar usuario
	if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
		return "", errors.New("usuario no encontrado")
	}

	// 2. Generar JWT
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":     user.ID,
		"user_id": user.ID,
		"role":    user.Role,
		"exp":     time.Now().Add(time.Hour * 24).Unix(),
	})

	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "secreto_super_seguro_cambiar_en_produccion"
	}

	return token.SignedString([]byte(secret))
}