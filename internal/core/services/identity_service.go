package services

import (
	"errors"
	"log"
	"time"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
)

type IdentityService struct{}

func NewIdentityService() *IdentityService {
	return &IdentityService{}
}

// VerifyIdentity simula el proceso de OCR y validación biométrica
func (s *IdentityService) VerifyIdentity(userID uint, imageURL string) error {
	// 1. Simulación de Latencia (Farming: Aquí iría la llamada a la IA de Python en el futuro)
	// Hacemos que el sistema espere 2 segundos para parecer que está procesando la imagen.
	time.Sleep(2 * time.Second)

	log.Printf("🤖 [MOCK OCR] Procesando imagen: %s para usuario %d", imageURL, userID)

	// 2. Validación "Fake"
	// En un sistema real, aquí la IA nos diría si leyó el RUT correctamente.
	// Por ahora, solo validamos que la URL no esté vacía.
	if imageURL == "" {
		return errors.New("no se ha proporcionado una imagen del documento")
	}

	// 3. Buscar al usuario
	var user domain.User
	if err := database.DB.First(&user, userID).Error; err != nil {
		return errors.New("usuario no encontrado")
	}

	// 4. Actualizar estado (R-SEC-01 cumplido)
	// GORM update: actualizamos solo el campo IsVerified
	user.IsVerified = true
	if err := database.DB.Save(&user).Error; err != nil {
		return err
	}

	log.Printf("✅ [MOCK OCR] Identidad verificada para el RUN: %s", user.Run)
	return nil
}