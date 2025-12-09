package http

import (
	"net/http"
	"strconv"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services" // <--- Ajustar
	"github.com/gin-gonic/gin"
)

type MatchHandler struct {
	service *services.MatchService
}

func NewMatchHandler(s *services.MatchService) *MatchHandler {
	return &MatchHandler{service: s}
}

func (h *MatchHandler) GetMatches(c *gin.Context) {
	// Leer preferencias de la URL
	prefType := c.Query("type")
	prefBreed := c.Query("breed")
	
	// Convertir edad
	ageStr := c.Query("max_age")
	maxAge, _ := strconv.Atoi(ageStr)

	// Llamar al algoritmo
	// (Por simplicidad pasamos lat/long en 0, en futuro las leemos del usuario)
	matches, err := h.service.FindMatches(prefType, prefBreed, maxAge, 0, 0)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"matches_found": len(matches),
		"results":       matches,
	})
}