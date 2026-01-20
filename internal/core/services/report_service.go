package services

import (
	"encoding/json"
	"errors"
	"time"

	"gorm.io/gorm"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

type ReportService struct {
	db          *gorm.DB
	authService *AuthService
}

func NewReportService(db *gorm.DB, authService *AuthService) *ReportService {
	return &ReportService{
		db:          db,
		authService: authService,
	}
}

// CreateReport: El usuario envía un reporte
func (s *ReportService) CreateReport(reporterID, reportedID, matchID uint, category, description string) error {
	if reporterID == reportedID {
		return errors.New("no puedes reportarte a ti mismo")
	}

	report := domain.Report{
		ReporterID:  reporterID,
		ReportedID:  reportedID,
		MatchID:     matchID,
		Category:    category,
		Description: description,
		Status:      "pending",
	}

	return s.db.Create(&report).Error
}

// GetReportDetails: Para el Dashboard. Trae el reporte y el CHAT asociado.
func (s *ReportService) GetReportDetails(reportID uint) (*domain.Report, []domain.Message, error) {
	var report domain.Report
	if err := s.db.Preload("Reporter").Preload("Reported").First(&report, reportID).Error; err != nil {
		return nil, nil, err
	}

	// Traer historial del chat (Contexto)
	var messages []domain.Message
	if report.MatchID != 0 {
		s.db.Where("match_id = ?", report.MatchID).Order("created_at asc").Find(&messages)
	}

	return &report, messages, nil
}

// GetAllPending: Lista para el dashboard principal
func (s *ReportService) GetAllPending() ([]domain.Report, error) {
	var reports []domain.Report
	err := s.db.Preload("Reporter").Preload("Reported").
		Where("status = ?", "pending").
		Order("created_at desc").
		Find(&reports).Error
	return reports, err
}

// ResolveReport: El Juez Admin dicta sentencia
func (s *ReportService) ResolveReport(adminID, reportID uint, action string, publicBlacklist bool) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var report domain.Report
		if err := tx.First(&report, reportID).Error; err != nil {
			return err
		}

		// 1. Acciones
		if action == "ban" {
			// A. Banear Usuario
			if err := tx.Model(&domain.User{}).Where("id = ?", report.ReportedID).Update("is_banned", true).Error; err != nil {
				return err
			}

			// B. Blacklist (Opcional)
			if publicBlacklist {
				var user domain.User
				tx.First(&user, report.ReportedID)
				
				entry := domain.BlacklistEntry{
					Run:    user.Run,
					Name:   user.Name,
					Reason: report.Category, // Usamos la categoría como razón pública
				}
				tx.Where("run = ?", user.Run).FirstOrCreate(&entry)
			}
		}

		// 2. Snapshot de Evidencia (Inmutable)
		if report.MatchID != 0 {
			var messages []domain.Message
			tx.Where("match_id = ?", report.MatchID).Order("created_at asc").Find(&messages)
			
			// Serializamos a JSON para guardarlo como texto congelado
			evidenceJSON, _ := json.Marshal(messages)
			report.EvidenceSnapshot = string(evidenceJSON)
		}

		// 3. Cerrar Reporte
		now := time.Now()
		report.Status = "resolved"
		report.ResolverID = &adminID
		report.ResolvedAt = &now
		
		return tx.Save(&report).Error
	})
}

// SearchBlacklist: Búsqueda pública por RUT
func (s *ReportService) SearchBlacklist(rut string) (*domain.BlacklistEntry, error) {
	var entry domain.BlacklistEntry
	err := s.db.Where("run = ?", rut).First(&entry).Error
	return &entry, err
}