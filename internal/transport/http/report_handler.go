// Package http contains the HTTP handlers for the application.
package http

import (
	"net/http"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

// =========================================================================
// Request & Response Structures
// =========================================================================

// CreateReportRequest defines the structure for creating a new report.
type CreateReportRequest struct {
	ReportedID  uint   `json:"reported_id" binding:"required"`
	MatchID     uint   `json:"match_id"` // Optional, but ideal to send
	Category    string `json:"category" binding:"required"`
	Description string `json:"description"`
}

// =========================================================================
// Handler Definition
// =========================================================================

// ReportHandler handles report-related HTTP requests.
type ReportHandler struct {
	service *services.ReportService
}

// NewReportHandler creates a new ReportHandler.
func NewReportHandler(s *services.ReportService) *ReportHandler {
	return &ReportHandler{service: s}
}

// =========================================================================
// Handler Methods
// =========================================================================

// Create handles the POST /report endpoint to create a new user report.
func (h *ReportHandler) Create(c *gin.Context) {
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	// Safely extract user ID regardless of its underlying type from the middleware
	var reporterID uint
	switch v := userIDVal.(type) {
	case float64:
		reporterID = uint(v)
	case uint:
		reporterID = v
	case int:
		reporterID = uint(v)
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal session error"})
		return
	}

	var req CreateReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Incomplete data"})
		return
	}

	err := h.service.CreateReport(reporterID, req.ReportedID, req.MatchID, req.Category, req.Description)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Report sent. An administrator will review the case."})
}

// SearchBlacklist handles the GET /blacklist/search?rut=... endpoint (Public).
func (h *ReportHandler) SearchBlacklist(c *gin.Context) {
	rut := c.Query("rut")
	if rut == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "A RUT must be provided"})
		return
	}

	entry, err := h.service.SearchBlacklist(rut)
	if err != nil {
		// Not found is good news
		c.JSON(http.StatusOK, gin.H{"found": false, "message": "No records found"})
		return
	}

	// Found is an alert
	c.JSON(http.StatusOK, gin.H{
		"found":  true,
		"name":   entry.Name,
		"reason": entry.Reason,
		"date":   entry.CreatedAt,
	})
}
