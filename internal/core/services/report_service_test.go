package services

import (
	"testing"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

func TestThreeStrikesBan(t *testing.T) {
	db := setupTestDB() // Reutilizamos tu helper de SQLite
	if err := db.AutoMigrate(&domain.User{}, &domain.Report{}, &domain.BlacklistEntry{}); err != nil {
		t.Fatal("Falló migración:", err)
	}
	authService := NewAuthService(db)
	reportService := NewReportService(db, authService)

	// 1. Crear un usuario "Víctima"
	victim := domain.User{Name: "Villano", Email: "bad@paws.cl", Run: "99.999.999-9"}
	db.Create(&victim)

	_ = reportService.CreateReport(2, victim.ID, 0, "user", "Acoso 1")
	_ = reportService.CreateReport(3, victim.ID, 0, "user", "Acoso 2")

	// Verificar que NO esté baneado
	isBanned, _ := authService.CheckBlacklist(victim.Run)
	if isBanned {
		t.Error("El usuario fue baneado con solo 2 reportes (Prematuro)")
	}

	// 3. Reportarlo la 3ra vez (GATILLO)
	_ = reportService.CreateReport(4, victim.ID, 0, "user", "Acoso 3")

	// Verificar que AHORA SÍ esté baneado
	isBanned, _ = authService.CheckBlacklist(victim.Run)
	if !isBanned {
		t.Error("El usuario NO fue baneado tras 3 reportes (Fallo de seguridad)")
	}
}
