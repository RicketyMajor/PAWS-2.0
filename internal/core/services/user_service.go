package services

import (
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

type UserService struct {
	db *gorm.DB
}

func NewUserService(db *gorm.DB) *UserService {
	return &UserService{db: db}
}

// UpdateIdentity actualiza los datos visibles del perfil
func (s *UserService) UpdateIdentity(userID uint, name, bio, phone, photoURL string) error {
	updates := map[string]interface{}{
		"name":      name,
		"bio":       bio,
		"phone":     phone,
		"photo_url": photoURL,
	}
	return s.db.Model(&domain.User{}).Where("id = ?", userID).Updates(updates).Error
}

// GetUser obtiene la info completa
func (s *UserService) GetUser(userID uint) (*domain.User, error) {
	var user domain.User
	err := s.db.First(&user, userID).Error
	return &user, err
}

// --- NUEVO: Guardar Token FCM ---
func (s *UserService) UpdateFCMToken(userID uint, token string) error {
	// Actualizamos solo el campo FCMToken
	return s.db.Model(&domain.User{}).Where("id = ?", userID).Update("fcm_token", token).Error
}

// GetUserProfile obtiene el perfil extendido
func (s *UserService) GetUserProfile(userID uint) (*domain.UserProfile, error) {
	var profile domain.UserProfile
	err := s.db.Where("user_id = ?", userID).First(&profile).Error
	return &profile, err
}

// UpdateFullProfile actualiza ambas tablas: users y user_profiles
func (s *UserService) UpdateFullProfile(userID uint, userUpdates map[string]interface{}, profileData *domain.UserProfile) error {
	tx := s.db.Begin() // Iniciamos transacción

	// 1. Actualizar datos base en tabla users
	if err := tx.Model(&domain.User{}).Where("id = ?", userID).Updates(userUpdates).Error; err != nil {
		tx.Rollback()
		return err
	}

	// 2. Crear o Actualizar tabla user_profiles (Upsert)
	var existingProfile domain.UserProfile
	err := tx.Where("user_id = ?", userID).First(&existingProfile).Error
	if err == gorm.ErrRecordNotFound {
		// Si no existe, lo creamos
		profileData.UserID = userID
		if err := tx.Create(profileData).Error; err != nil {
			tx.Rollback()
			return err
		}
	} else {
		// Si existe, lo actualizamos
		profileData.ID = existingProfile.ID
		if err := tx.Model(&existingProfile).Updates(profileData).Error; err != nil {
			tx.Rollback()
			return err
		}
	}

	return tx.Commit().Error // Confirmar transacción
}
