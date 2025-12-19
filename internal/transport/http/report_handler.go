package http

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

type ReportRequest struct {
	ReportedID uint   `json:"reported_id" binding:"required"`
	Reason     string `json:"reason" binding:"required"`
}

type ReportHandler struct {
	service *services.ReportService
}

func NewReportHandler(s *services.ReportService) *ReportHandler {
	return &ReportHandler{service: s}
}

func (h *ReportHandler) Create(c *gin.Context) {
	// Obtener ID del usuario que está reportando (viene del Token)
	// Nota: Necesitas que tu middleware ponga el "userID" en el contexto.
	// Por ahora asumiremos que lo obtenemos o simulamos.
	reporterID := c.GetUint("userID") 
	if reporterID == 0 {
		// Fallback si el middleware no está configurado completo aún
		reporterID = 1 
	}

	var req ReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.service.CreateReport(reporterID, req.ReportedID, req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Reporte recibido. Gracias por ayudar a la comunidad."})
}