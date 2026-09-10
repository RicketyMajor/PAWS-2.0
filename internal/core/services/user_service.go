// Package services contains the core business logic of the application.
package services

import (
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

// =========================================================================
// Service Definition
// =========================================================================

// UserService provides business logic for user-related operations.
type UserService struct {
	db *gorm.DB
}

// NewUserService creates a new UserService.
func NewUserService(db *gorm.DB) *UserService {
	return &UserService{db: db}
}

// =========================================================================
// Profile Management
// =========================================================================

// UpdateIdentity updates a user's basic profile information and synchronizes the photo URL.
func (s *UserService) UpdateIdentity(userID uint, name, bio, phone, photoURL string) error {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// 1. Get current user to know their email for synchronization.
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

	// 2. Update the profile that made the request.
	if err := tx.Model(&domain.User{}).Where("id = ?", userID).Updates(updates).Error; err != nil {
		tx.Rollback()
		return err
	}

	// 3. Magically synchronize the photo URL on the dual-role account (if it exists).
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

// GetUser retrieves the full user object by ID.
func (s *UserService) GetUser(userID uint) (*domain.User, error) {
	var user domain.User
	err := s.db.First(&user, userID).Error
	return &user, err
}

// GetUserProfile retrieves the extended user profile information.
func (s *UserService) GetUserProfile(userID uint) (*domain.UserProfile, error) {
	var profile domain.UserProfile
	err := s.db.Where("user_id = ?", userID).First(&profile).Error
	return &profile, err
}

// UpdateFullProfile updates both the base user data and the extended profile data in a single transaction.
func (s *UserService) UpdateFullProfile(userID uint, userUpdates map[string]interface{}, profileData *domain.UserProfile) error {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	// 1. Update base user data in the 'users' table.
	if err := tx.Model(&domain.User{}).Where("id = ?", userID).Updates(userUpdates).Error; err != nil {
		tx.Rollback()
		return err
	}

	// If a photo URL is part of the update, synchronize it with the dual-role account.
	if photoURL, ok := userUpdates["photo_url"]; ok && photoURL != "" {
		var currentUser domain.User
		if err := tx.First(&currentUser, userID).Error; err == nil {
			tx.Model(&domain.User{}).
				Where("email = ? AND id != ?", currentUser.Email, userID).
				Update("photo_url", photoURL)
		}
	}

	// 2. Create or Update the 'user_profiles' table (Upsert).
	var existingProfile domain.UserProfile
	err := tx.Where("user_id = ?", userID).First(&existingProfile).Error
	if err == gorm.ErrRecordNotFound {
		// If profile doesn't exist, create it.
		profileData.UserID = userID
		if err := tx.Create(profileData).Error; err != nil {
			tx.Rollback()
			return err
		}
	} else {
		// If profile exists, update it.
		profileData.ID = existingProfile.ID
		if err := tx.Model(&existingProfile).Updates(profileData).Error; err != nil {
			tx.Rollback()
			return err
		}
	}

	return tx.Commit().Error
}
