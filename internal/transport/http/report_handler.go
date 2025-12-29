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
	// CORRECCIÓN DE SEGURIDAD
	// Replicamos la lógica segura. Si tienes el helper en otro lado, úsalo.
	idVal, exists := c.Get("userID")
	var reporterID uint
	
	if exists {
		switch v := idVal.(type) {
		case float64:
			reporterID = uint(v)
		case uint:
			reporterID = v
		}
	}

	if reporterID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "No se pudo identificar al usuario"})
		return 
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