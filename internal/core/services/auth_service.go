package services

import (
	"errors"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain" // <--- CAMBIA ESTO
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database" // <--- CAMBIA ESTO
	"golang.org/x/crypto/bcrypt"
)

// AuthService agrupa la lógica de registro y login
type AuthService struct{}

func NewAuthService() *AuthService {
	return &AuthService{}
}

// Register crea un nuevo usuario aplicando reglas de seguridad
func (s *AuthService) Register(name, email, password, run, role string) (*domain.User, error) {
	// 1. Verificar si el RUN ya existe (R-SEC-02)
	var existingUser domain.User
	// Buscamos en la BD si alguien tiene ese RUN
	result := database.DB.Where("run = ?", run).First(&existingUser)
	if result.Error == nil {
		// Si NO hubo error al buscar, significa que LO ENCONTRÓ -> Bloqueamos
		return nil, errors.New("el RUN ya está registrado en el sistema")
	}

	// 2. Verificar si el Email ya existe
	result = database.DB.Where("email = ?", email).First(&existingUser)
	if result.Error == nil {
		return nil, errors.New("el correo electrónico ya está registrado")
	}

	// 3. Hashear la contraseña (Seguridad básica)
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	// 4. Crear el objeto Usuario
	newUser := domain.User{
		Name:       name,
		Email:      email,
		Run:        run,
		Password:   string(hashedPassword),
		Role:       role,
		IsVerified: false, // Por defecto no verificado (R-SEC-01)
		IsBanned:   false,
	}

	// 5. Guardar en Base de Datos
	if err := database.DB.Create(&newUser).Error; err != nil {
		return nil, err
	}

	return &newUser, nil
}