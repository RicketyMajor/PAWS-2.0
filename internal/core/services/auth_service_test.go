package services

import (
	"testing"
	"github.com/glebarez/sqlite" // Driver ligero para tests
	"gorm.io/gorm"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

// UT-SEC-01: Validación lógica de antecedentes en Blacklist 
// setupTestDB crea una base de datos en memoria y crea la tabla automáticamente
func setupTestDB() *gorm.DB {
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		panic("falló al conectar a base de datos de prueba")
	}
	// Migración automática: Crea la tabla BlacklistEntry en la memoria RAM
	db.AutoMigrate(&domain.BlacklistEntry{})
	return db
}

func TestCheckBlacklist(t *testing.T) {
	// 1. Preparamos la DB falsa
	db := setupTestDB()
	
	// 2. Insertamos el dato de prueba (Mock real en BD)
	bannedRun := "12345678-9"
	db.Create(&domain.BlacklistEntry{Run: bannedRun, Reason: "Maltrato"})

	// 3. Inicializamos el servicio con la DB falsa
	service := NewAuthService(db)

	// Caso 1: RUN Baneado
	t.Run("Debe retornar TRUE si el RUN está en blacklist", func(t *testing.T) {
		isBanned, err := service.CheckBlacklist(bannedRun)
		if err != nil {
			t.Errorf("Error inesperado: %v", err)
		}
		if !isBanned {
			t.Error("Falló: El usuario debería estar baneado")
		}
	})

	// Caso 2: RUN Limpio
	t.Run("Debe retornar FALSE si el RUN está limpio", func(t *testing.T) {
		cleanRun := "11111111-1"
		isBanned, err := service.CheckBlacklist(cleanRun)
		if err != nil {
			t.Errorf("Error inesperado: %v", err)
		}
		if isBanned {
			t.Error("Falló: El usuario NO debería estar baneado")
		}
	})

	// Caso 3: Error
	t.Run("Debe retornar Error si el RUN está vacío", func(t *testing.T) {
		_, err := service.CheckBlacklist("")
		if err == nil {
			t.Error("Falló: Se esperaba error por RUN vacío")
		}
	})
}