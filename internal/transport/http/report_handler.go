package http

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
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
	userIDVal, _ := c.Get("userID")
	reporterID := uint(userIDVal.(float64)) // Asumiendo cast seguro previo

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