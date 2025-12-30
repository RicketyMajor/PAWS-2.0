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

		fmt.Printf("USUARIO BANEADO AUTOMÁTICAMENTE: %s (%s)\n", user.Name, user.Run)
	}

	return nil
}

// GetAllReports: Lista todas las denuncias para el Admin (Cargando nombres de usuarios)
func (s *ReportService) GetAllReports() ([]domain.Report, error) {
	var reports []domain.Report
	// Asumimos que en tu modelo domain.Report tienes las relaciones:
	// Reporter User `gorm:"foreignKey:ReporterID"`
	// Reported User `gorm:"foreignKey:ReportedID"`
	// Si no las tienes, GORM traerá solo los IDs, que sirve igual para el MVP.
	err := s.db.Preload("Reporter").Preload("Reported").
		Order("created_at desc").
		Find(&reports).Error
	return reports, err
}

// BanUserManual: El botón de pánico del Admin
func (s *ReportService) BanUserManual(adminID, targetUserID uint, reason string) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// 1. Buscar al usuario objetivo
		var user domain.User
		if err := tx.First(&user, targetUserID).Error; err != nil {
			return err
		}

		// 2. Marcarlo como baneado en la tabla users
		if err := tx.Model(&user).Update("is_banned", true).Error; err != nil {
			return err
		}

		// 3. Crear entrada en Blacklist (para que no se registre de nuevo con el mismo RUT)
		blacklistEntry := domain.BlacklistEntry{
			Run:    user.Run,
			Reason: fmt.Sprintf("Baneado por Admin #%d: %s", adminID, reason),
		}
		// Usamos FirstOrCreate para no fallar si ya estaba en blacklist
		if err := tx.Where("run = ?", user.Run).FirstOrCreate(&blacklistEntry).Error; err != nil {
			return err
		}

		return nil
	})
}