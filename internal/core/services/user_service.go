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