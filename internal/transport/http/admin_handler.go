// Package http contains the HTTP handlers for the application.
package http

import (
	"net/http"
	"strconv"
	"github.com/gin-gonic/gin"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

// =========================================================================
// Handler Definition
// =========================================================================

// AdminHandler handles admin-only HTTP requests, primarily for managing reports.
type AdminHandler struct {
	service *services.ReportService 
}

// NewAdminHandler creates a new AdminHandler.
func NewAdminHandler(s *services.ReportService) *AdminHandler {
	return &AdminHandler{service: s} 
}

// =========================================================================
// Handler Methods
// =========================================================================

// GetReports handles GET /admin/reports to fetch all pending reports.
func (h *AdminHandler) GetReports(c *gin.Context) {
	reports, err := h.service.GetAllPending()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error loading reports"})
		return
	}
	c.JSON(http.StatusOK, reports)
}

// GetReportDetails handles GET /admin/reports/:id to fetch the details of a specific report.
func (h *AdminHandler) GetReportDetails(c *gin.Context) {
	idStr := c.Param("id")
	id, _ := strconv.Atoi(idStr)

	report, messages, err := h.service.GetReportDetails(uint(id))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Report not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"report":   report,
		"evidence": messages, // The full chat history for context
	})
}

// Resolve handles POST /admin/reports/:id/resolve to close a report.
func (h *AdminHandler) Resolve(c *gin.Context) {
	adminIDVal, _ := c.Get("userID")
	adminID := uint(adminIDVal.(float64))

	idStr := c.Param("id")
	id, _ := strconv.Atoi(idStr)

	var req struct {
		Action          string `json:"action" binding:"required"` // 'ban' or 'dismiss'
		PublicBlacklist bool   `json:"public_blacklist"`          // Toggle for public blacklist
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.service.ResolveReport(adminID, uint(id), req.Action, req.PublicBlacklist)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error resolving report"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Case closed successfully"})
}