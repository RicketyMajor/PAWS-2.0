package services

import (
	"errors"
	"fmt"
	"os"
	"time"
	"gorm.io/gorm"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain" // <--- CAMBIA ESTO
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database" // <--- CAMBIA ESTO
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// AuthService agrupa la lógica de registro y login
type AuthService struct{
	db *gorm.DB
}

func NewAuthService(dbOrNil *gorm.DB) *AuthService {
	if dbOrNil == nil {
		return &AuthService{db: database.DB}
	}
	return &AuthService{db: dbOrNil}
}

// Register crea un nuevo usuario aplicando reglas de seguridad
func (s *AuthService) Register(name, email, password, run, role string) (*domain.User, error) {
	// --- NUEVO: Validación R-SEC-03 (Blacklist) ---
	var blacklistEntry domain.BlacklistEntry
	// Buscamos si el RUN está en la lista negra
	if err := database.DB.Where("run = ?", run).First(&blacklistEntry).Error; err == nil {
		// Si err == nil, significa que LO ENCONTRÓ. ¡Peligro!
		return nil, errors.New("registro rechazado: este RUN se encuentra en nuestra lista de bloqueo por: " + blacklistEntry.Reason)
	}
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

func (s *AuthService) Login(email, password string) (string, error) {
	var user domain.User

	// 1. Buscar usuario
	result := database.DB.Where("email = ?", email).First(&user)
	if result.Error != nil {
		return "", errors.New("credenciales inválidas") // No decir "usuario no encontrado" por seguridad
	}

	// 2. Verificar si está Baneado (R-SEC-03)
	// Si "Evil PAWS" marcó a este usuario, no lo dejamos entrar.
	if user.IsBanned {
		return "", errors.New("tu cuenta ha sido suspendida por violar las normas de seguridad")
	}

	// 3. Verificar Contraseña
	// Comparamos el hash de la BD con la contraseña que nos mandan ahora
	err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password))
	if err != nil {
		return "", errors.New("credenciales inválidas")
	}

	// 4. Generar JWT
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  user.ID,   // Subject (Quién es)
		"role": user.Role, // Rol (Permisos)
		"exp":  time.Now().Add(time.Hour * 24).Unix(), // Expira en 24 horas
	})

	// Firmar el token con una clave secreta (Debería estar en .env, por ahora usamos un default)
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

// CheckBlacklist VERSIÓN REAL (Conectada a BD)
func (s *AuthService) CheckBlacklist(run string) (bool, error) {
	if run == "" {
		return false, fmt.Errorf("el RUN no puede estar vacío")
	}

	var entry domain.BlacklistEntry
	
	// Buscamos en la tabla 'blacklist_entries'
	// SELECT * FROM blacklist_entries WHERE run = '12345678-9' LIMIT 1
	result := s.db.Where("run = ?", run).First(&entry)

	if result.Error != nil {
		if result.Error == gorm.ErrRecordNotFound {
			// No se encontró -> No está baneado -> Retorna FALSE
			return false, nil 
		}
		// Hubo otro error (ej: DB caída)
		return false, result.Error
	}

	// Si lo encontró -> Está baneado -> Retorna TRUE
	return true, nil
}