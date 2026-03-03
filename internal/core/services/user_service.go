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

// UpdateIdentity actualiza los datos visibles del perfil y sincroniza la foto
func (s *UserService) UpdateIdentity(userID uint, name, bio, phone, photoURL string) error {
	tx := s.db.Begin()

	// 1. Obtener el usuario actual para saber su email
	var currentUser domain.User
	if err := tx.First(&currentUser, userID).Error; err != nil {
		tx.Rollback()
		return err
	}

	updates := map[string]interface{}{
		"name":      name,
		"bio":       bio,
		"phone":     phone,
		"photo_url": photoURL,
	}

	// 2. Actualizar la cuenta que hizo la petición
	if err := tx.Model(&domain.User{}).Where("id = ?", userID).Updates(updates).Error; err != nil {
		tx.Rollback()
		return err
	}

	// 3. Sincronizar mágicamente la foto en la cuenta dual (si tiene el mismo email)
	if photoURL != "" {
		if err := tx.Model(&domain.User{}).
			Where("email = ? AND id != ?", currentUser.Email, userID).
			Update("photo_url", photoURL).Error; err != nil {
			tx.Rollback()
			return err
		}
	}

	return tx.Commit().Error
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

// UpdateFullProfile actualiza ambas tablas y sincroniza la foto
func (s *UserService) UpdateFullProfile(userID uint, userUpdates map[string]interface{}, profileData *domain.UserProfile) error {
	tx := s.db.Begin() // Iniciamos transacción

	// 1. Actualizar datos base en tabla users
	if err := tx.Model(&domain.User{}).Where("id = ?", userID).Updates(userUpdates).Error; err != nil {
		tx.Rollback()
		return err
	}

	// NUEVO: Si la foto viene en los updates, sincronizar con la cuenta dual
	if photoURL, ok := userUpdates["photo_url"]; ok && photoURL != "" {
		var currentUser domain.User
		if err := tx.First(&currentUser, userID).Error; err == nil {
			tx.Model(&domain.User{}).
				Where("email = ? AND id != ?", currentUser.Email, userID).
				Update("photo_url", photoURL)
		}
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
