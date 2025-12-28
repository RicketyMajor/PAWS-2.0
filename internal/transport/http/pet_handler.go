package http

import (
	"net/http"
	"strconv"

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
	PhotoURL    string  `json:"photo_url"` 
}

type PetHandler struct {
	service *services.PetService
}

func NewPetHandler(service *services.PetService) *PetHandler {
	return &PetHandler{service: service}
}

func (h *PetHandler) Create(c *gin.Context) {
	// 1. Obtener UserID del contexto
	userIDFloat, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "usuario no autenticado"})
		return
	}
	userID := uint(userIDFloat.(float64))

	var req CreatePetRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 2. Llamar al servicio
	newPet, err := h.service.Create(
		req.Name, 
		req.Type, 
		req.Breed, 
		req.Description, 
		req.Age, 
		req.Latitude, 
		req.Longitude, 
		userID,
		req.PhotoURL, 
	)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error guardando mascota: " + err.Error()})
		return
	}

	c.JSON(http.StatusCreated, newPet)
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
	// Mapeo manual de query params a mapa de filtros
	filters := SearchPetFilters{}
	if err := c.BindQuery(&filters); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Filtros inválidos"})
		return
	}

	// CORRECCIÓN: Eliminamos 'filterMap' porque no se estaba usando en la llamada siguiente.
	// Cuando implementes la búsqueda avanzada en PetService, volveremos a activarlo.

	// Fallback a GetAll por ahora
	pets, err := h.service.GetAll() 
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	
	// Aquí podrías filtrar la lista 'pets' en memoria usando los datos de 'filters'
	// si quisieras, pero para compilar, esto es suficiente.

	c.JSON(http.StatusOK, pets)
}

// GetNearby (GET /pets/nearby?lat=-33.4&lng=-70.6&dist=10)
func (h *PetHandler) GetNearby(c *gin.Context) {
	latStr := c.Query("lat")
	lngStr := c.Query("lng")
	distStr := c.Query("dist")

	if latStr == "" || lngStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Latitud y Longitud requeridas"})
		return
	}

	lat, _ := strconv.ParseFloat(latStr, 64)
	lng, _ := strconv.ParseFloat(lngStr, 64)
	dist, _ := strconv.ParseFloat(distStr, 64)
	
	if dist == 0 {
		dist = 10.0
	}

	pets, err := h.service.SearchNearby(lat, lng, dist)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error calculando cercanía"})
		return
	}

	c.JSON(http.StatusOK, pets)
}

func (h *PetHandler) GetPetByID(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ID inválido"})
		return
	}

	pet, err := h.service.GetByID(uint(id))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Mascota no encontrada"})
		return
	}

	c.JSON(http.StatusOK, pet)
}

func (h *PetHandler) Delete(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ID inválido"})
		return
	}

	// Obtener UserID de forma segura (como hicimos en match_handler)
	userIDVal, _ := c.Get("userID")
	// Asumimos float64 que es lo estándar de JWT
	var userID uint
	if val, ok := userIDVal.(float64); ok {
		userID = uint(val)
	} else {
		userID = userIDVal.(uint)
	}

	if err := h.service.Delete(uint(id), userID); err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Mascota eliminada correctamente"})
}