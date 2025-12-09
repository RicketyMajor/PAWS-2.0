package http

import (
	"net/http"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

type CreatePetRequest struct {
	Name        string  `json:"name" binding:"required"`
	Type        string  `json:"type" binding:"required"`
	Breed       string  `json:"breed"`
	Age         int     `json:"age"`
	Description string  `json:"description"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
}

type PetHandler struct {
	service *services.PetService
}

func NewPetHandler(service *services.PetService) *PetHandler {
	return &PetHandler{service: service}
}

func (h *PetHandler) Create(c *gin.Context) {
	// 1. Obtener UserID del contexto (gracias al Middleware)
	userIDFloat, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "usuario no autenticado"})
		return
	}
	// JWT devuelve números como float64, hay que convertir a uint
	userID := uint(userIDFloat.(float64))

	// 2. Leer JSON
	var req CreatePetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 3. Llamar servicio
	pet, err := h.service.Create(req.Name, req.Type, req.Breed, req.Description, req.Age, req.Latitude, req.Longitude, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, pet)
}

func (h *PetHandler) GetAll(c *gin.Context) {
	pets, err := h.service.GetAll()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, pets)
}