package http

import (
	"net/http"
	"strconv"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

type AdminHandler struct {
	service *services.ReportService 
}

func NewAdminHandler(s *services.ReportService) *AdminHandler {
	return &AdminHandler{service: s} 
}

// GetReports (GET /admin/reports) - Solo pendientes
func (h *AdminHandler) GetReports(c *gin.Context) {
	reports, err := h.service.GetAllPending()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error cargando reportes"})
		return
	}
	c.JSON(http.StatusOK, reports)
}

// GetReportDetails (GET /admin/reports/:id) - EL CONTEXTO
func (h *AdminHandler) GetReportDetails(c *gin.Context) {
	idStr := c.Param("id")
	id, _ := strconv.Atoi(idStr)

	report, messages, err := h.service.GetReportDetails(uint(id))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Reporte no encontrado"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"report":   report,
		"evidence": messages, // El chat completo para el juez
	})
}

// Resolve (POST /admin/reports/:id/resolve)
func (h *AdminHandler) Resolve(c *gin.Context) {
	adminIDVal, _ := c.Get("userID")
	adminID := uint(adminIDVal.(float64))

	idStr := c.Param("id")
	id, _ := strconv.Atoi(idStr)

	var req struct {
		Action          string `json:"action" binding:"required"` // 'ban' o 'dismiss'
		PublicBlacklist bool   `json:"public_blacklist"`          // Toggle para blacklist pública
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.service.ResolveReport(adminID, uint(id), req.Action, req.PublicBlacklist)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error resolviendo reporte"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Caso cerrado exitosamente"})
}