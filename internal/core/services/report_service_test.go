package services

import (
	"testing"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

func TestThreeStrikesBan(t *testing.T) {
	db := setupTestDB() // Reutilizamos tu helper de SQLite
	db.AutoMigrate(&domain.User{}, &domain.Report{}, &domain.BlacklistEntry{})

	authService := NewAuthService(db)
	reportService := NewReportService(db, authService)

	// 1. Crear un usuario "Víctima"
	victim := domain.User{Name: "Villano", Email: "bad@paws.cl", Run: "99.999.999-9"}
	db.Create(&victim)

	// 2. Reportarlo 2 veces (No debería pasar nada)
	reportService.CreateReport(2, victim.ID, "Acoso 1")
	reportService.CreateReport(3, victim.ID, "Acoso 2")

	// Verificar que NO esté baneado
	isBanned, _ := authService.CheckBlacklist(victim.Run)
	if isBanned {
		t.Error("El usuario fue baneado con solo 2 reportes (Prematuro)")
	}

	// 3. Reportarlo la 3ra vez (GATILLO)
	reportService.CreateReport(4, victim.ID, "Acoso 3")

	// Verificar que AHORA SÍ esté baneado
	isBanned, _ = authService.CheckBlacklist(victim.Run)
	if !isBanned {
		t.Error("El usuario NO fue baneado tras 3 reportes (Fallo de seguridad)")
	}
}