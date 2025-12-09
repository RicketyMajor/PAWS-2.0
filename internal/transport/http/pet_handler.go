package http

import (
	"net/http"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

type SearchPetFilters struct {
	Type   string  `form:"type"`   // Ej: Dog, Cat
	Breed  string  `form:"breed"`  // Ej: Golden Retriever
	Lat    float64 `form:"lat"`    // Latitud del usuario
	Long   float64 `form:"long"`   // Longitud del usuario
	Radius float64 `form:"radius"` // Radio de búsqueda en KM
	MaxAge int     `form:"max_age"`
}

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

func (h *PetHandler) Search(c *gin.Context) {
	var filters SearchPetFilters

	// ShouldBindQuery lee los parámetros de la URL (?type=Dog&...)
	if err := c.ShouldBindQuery(&filters); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "parámetros de búsqueda inválidos"})
		return
	}

	// Convertimos el struct a un mapa para el servicio (más flexible)
	filterMap := map[string]interface{}{
		"type":   filters.Type,
		"breed":  filters.Breed,
		"lat":    filters.Lat,
		"long":   filters.Long,
		"radius": filters.Radius,
		"max_age": filters.MaxAge,
	}

	pets, err := h.service.Search(filterMap)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, pets)
}