package http

import (
	"net/http"
	"strconv"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

type AdminHandler struct {
    // CORRECCIÓN: Cambiamos el nombre del campo de 'reportService' a 'service'
	service *services.ReportService 
}

func NewAdminHandler(s *services.ReportService) *AdminHandler {
	return &AdminHandler{service: s} // Ahora sí coincide
}
// GetReports (GET /admin/reports)
func (h *AdminHandler) GetReports(c *gin.Context) {
	reports, err := h.service.GetAllReports()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error cargando reportes"})
		return
	}
	c.JSON(http.StatusOK, reports)
}

// BanUser (POST /admin/ban/:id)
func (h *AdminHandler) BanUser(c *gin.Context) {
	// Obtenemos ID del Admin (quien ejecuta la acción)
	adminIDVal, _ := c.Get("userID")
    // Conversión segura simple (asumiendo que ya aplicaste el fix de seguridad anterior)
    adminID := uint(adminIDVal.(float64))

	// Obtenemos ID del usuario a banear
	targetIDStr := c.Param("id")
	targetID, _ := strconv.Atoi(targetIDStr)

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Se requiere motivo (reason)"})
		return
	}

	err := h.service.BanUserManual(adminID, uint(targetID), req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error baneando usuario: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "JUSTICIA APLICADA: Usuario baneado."})
}