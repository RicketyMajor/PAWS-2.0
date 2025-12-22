package services

import (
	"errors"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

type UserService struct {
	db *gorm.DB
}

func NewUserService(db *gorm.DB) *UserService {
	return &UserService{db: db}
}

// CreateOrUpdateProfile guarda la información demográfica
func (s *UserService) CreateOrUpdateProfile(userID uint, profile domain.UserProfile) error {
	// Buscamos si ya existe
	var existing domain.UserProfile
	result := s.db.Where("user_id = ?", userID).First(&existing)

	if result.Error != nil && !errors.Is(result.Error, gorm.ErrRecordNotFound) {
		return result.Error // Error de BD real
	}

	if errors.Is(result.Error, gorm.ErrRecordNotFound) {
		// Crear nuevo
		profile.UserID = userID
		return s.db.Create(&profile).Error
	}

	// Actualizar existente
	// (GORM actualiza los campos no-cero)
	return s.db.Model(&existing).Updates(profile).Error
}

// GetProfile obtiene el perfil para el algoritmo
func (s *UserService) GetProfile(userID uint) (*domain.UserProfile, error) {
	var profile domain.UserProfile
	err := s.db.Where("user_id = ?", userID).First(&profile).Error
	if err != nil {
		return nil, err
	}
	return &profile, nil
}