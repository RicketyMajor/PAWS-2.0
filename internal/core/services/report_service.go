package services

import (
	"fmt"
	"gorm.io/gorm"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

type ReportService struct {
	db          *gorm.DB
	authService *AuthService // Necesitamos el AuthService para banear
}

func NewReportService(db *gorm.DB, authService *AuthService) *ReportService {
	return &ReportService{
		db:          db,
		authService: authService,
	}
}

// CreateReport registra una denuncia y verifica si se debe banear al usuario
func (s *ReportService) CreateReport(reporterID, reportedID uint, reason string) error {
	// 1. Evitar auto-reporte
	if reporterID == reportedID {
		return fmt.Errorf("no puedes reportarte a ti mismo")
	}

	// 2. Crear el reporte
	report := domain.Report{
		ReporterID: reporterID,
		ReportedID: reportedID,
		Reason:     reason,
		Status:     "verified", // Para este MVP asumimos que son verídicos automáticamente
	}

	if err := s.db.Create(&report).Error; err != nil {
		return err
	}

	// 3. LA REGLA DE LOS 3 STRIKES (R-SEC-04)
	return s.checkAndBanUser(reportedID)
}

func (s *ReportService) checkAndBanUser(userID uint) error {
	var count int64
	// Contamos reportes verificados
	s.db.Model(&domain.Report{}).
		Where("reported_id = ? AND status = ?", userID, "verified").
		Count(&count)

	// Si tiene 3 o más, procedemos al bloqueo automático
	if count >= 3 {
		// A. Obtener el RUN del usuario culpable
		var user domain.User
		if err := s.db.First(&user, userID).Error; err != nil {
			return err
		}

		// B. Agregarlo a la Blacklist usando el AuthService
		// Usamos una función interna o directa a la BD para no depender de HTTP
		blacklistEntry := domain.BlacklistEntry{
			Run:    user.Run,
			Reason: "Sistema: Acumulación de 3 reportes graves",
		}
		
		// Guardamos en Blacklist
		if err := s.db.Create(&blacklistEntry).Error; err != nil {
			// Si ya estaba baneado, ignoramos el error
			return nil 
		}

		fmt.Printf("🚫 USUARIO BANEADO AUTOMÁTICAMENTE: %s (%s)\n", user.Name, user.Run)
	}

	return nil
}