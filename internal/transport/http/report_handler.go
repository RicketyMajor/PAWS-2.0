package http

import (
	"net/http"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

type CreateReportRequest struct {
	ReportedID  uint   `json:"reported_id" binding:"required"`
	MatchID     uint   `json:"match_id"` // Opcional, pero ideal enviarlo
	Category    string `json:"category" binding:"required"`
	Description string `json:"description"`
}

type ReportHandler struct {
	service *services.ReportService
}

func NewReportHandler(s *services.ReportService) *ReportHandler {
	return &ReportHandler{service: s}
}

// Create (POST /report)
func (h *ReportHandler) Create(c *gin.Context) {
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no autenticado"})
		return
	}

	// Extracción segura del ID sin importar cómo lo inyecte el middleware
	var reporterID uint
	switch v := userIDVal.(type) {
	case float64:
		reporterID = uint(v)
	case uint:
		reporterID = v
	case int:
		reporterID = uint(v)
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error interno de sesión"})
		return
	}

	var req CreateReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Datos incompletos"})
		return
	}

	err := h.service.CreateReport(reporterID, req.ReportedID, req.MatchID, req.Category, req.Description)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Reporte enviado. Un administrador revisará el caso."})
}

// SearchBlacklist (GET /blacklist/search?rut=...) - PÚBLICO
func (h *ReportHandler) SearchBlacklist(c *gin.Context) {
	rut := c.Query("rut")
	if rut == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Debe ingresar un RUT"})
		return
	}

	entry, err := h.service.SearchBlacklist(rut)
	if err != nil {
		// No encontrado = Buena noticia
		c.JSON(http.StatusOK, gin.H{"found": false, "message": "Sin antecedentes"})
		return
	}

	// Encontrado = Alerta
	c.JSON(http.StatusOK, gin.H{
		"found":  true,
		"name":   entry.Name,
		"reason": entry.Reason,
		"date":   entry.CreatedAt,
	})
}
