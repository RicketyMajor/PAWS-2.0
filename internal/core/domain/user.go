package domain

import (

	"gorm.io/gorm"
)

// User representa a cualquier actor en el sistema (Adoptante, Rescatista, Admin).
// Usamos GORM para definir cómo se guardará esto en la base de datos automáticamente.
type User struct {
	// gorm.Model inyecta campos estándar: ID (uint), CreatedAt, UpdatedAt, DeletedAt (para soft delete)
	gorm.Model

	// Datos Personales Básicos
	Name  string `gorm:"not null" json:"name"`
	Email string `gorm:"uniqueIndex;not null" json:"email"` // uniqueIndex evita correos duplicados

	// Seguridad (Evil PAWS R-SEC-01 y R-SEC-02)
	// El RUN/RUT es CRÍTICO para evitar multicuentas. Debe ser único.
	Run string `gorm:"uniqueIndex;not null" json:"run"` 

	// Hash de la contraseña (NUNCA guardar en texto plano)
	Password string `gorm:"not null" json:"-"` // json:"-" hace que la contraseña nunca se envíe al frontend por error

	// Roles y Estado
	// Roles: "adopter", "rescuer", "admin"
	Role string `gorm:"default:'adopter'" json:"role"`
	
	// Verified indica si ya pasó el proceso de OCR del DNI (R-SEC-01)
	IsVerified bool `gorm:"default:false" json:"is_verified"`

	// Banned permite bloquear usuarios manualmente o automáticamente (R-SEC-03)
	IsBanned bool `gorm:"default:false" json:"is_banned"`
}
