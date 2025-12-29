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

// UpdateIdentity actualiza los datos visibles del perfil del usuario
func (s *UserService) UpdateIdentity(userID uint, name, bio, phone, photoURL string) error {
	// Usamos un mapa para actualizar solo los campos que queremos
	updates := map[string]interface{}{
		"name":      name,
		"bio":       bio,
		"phone":     phone,
		"photo_url": photoURL,
	}

	return s.db.Model(&domain.User{}).Where("id = ?", userID).Updates(updates).Error
}

// GetUser obtiene la info completa del usuario (para mostrar en su perfil)
func (s *UserService) GetUser(userID uint) (*domain.User, error) {
	var user domain.User
	err := s.db.First(&user, userID).Error
	return &user, err
}