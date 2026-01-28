package http

import (
	"net/http"
	"strconv"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

// --- ESTRUCTURAS DE DATOS ---
type SearchPetFilters struct {
	Type   string  `form:"type"`
	Breed  string  `form:"breed"`
	Lat    float64 `form:"lat"`
	Long   float64 `form:"long"`
	Radius float64 `form:"radius"`
	MaxAge int     `form:"max_age"`
}

type CreatePetForm struct {
	Name         string  `form:"name" binding:"required"`
	Type         string  `form:"type" binding:"required"`
	Breed        string  `form:"breed"`
	Age          int     `form:"age"`
	Description  string  `form:"description"`
	Latitude     float64 `form:"latitude"`
	Longitude    float64 `form:"longitude"`
	Address      string  `form:"address"`
	IsVaccinated bool    `form:"is_vaccinated"`
	IsSterilized bool    `form:"is_sterilized"`
	IsDewormed   bool    `form:"is_dewormed"`
	SpecialNeeds string  `form:"special_needs"`
	RequiresYard bool    `form:"requires_yard"`
	GoodWithKids bool    `form:"good_with_kids"`
	GoodWithDogs bool    `form:"good_with_dogs"`
	EnergyLevel  string  `form:"energy_level"`
}

type PetHandler struct {
	service     *services.PetService
	fileService *services.FileService
}

func NewPetHandler(service *services.PetService, fileService *services.FileService) *PetHandler {
	return &PetHandler{
		service:     service,
		fileService: fileService,
	}
}

// Create maneja la creación con imágenes múltiples
func (h *PetHandler) Create(c *gin.Context) {
	userIDFloat, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "no auth"})
		return
	}
	
	var userID uint
	if val, ok := userIDFloat.(float64); ok {
		userID = uint(val)
	} else if val, ok := userIDFloat.(uint); ok {
		userID = val
	} else {
		userID = userIDFloat.(uint)
	}

	var form CreatePetForm
	if err := c.ShouldBind(&form); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Datos inválidos: " + err.Error()})
		return
	}

	formMultipart, err := c.MultipartForm()
	var imageURLs []string

	if err == nil {
		files := formMultipart.File["images"]
		if len(files) > 0 {
			if len(files) > 10 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Máximo 10 fotos permitidas"})
				return
			}
			uploadedURLs, err := h.fileService.SaveMultipleImages(c.Request.Context(), files)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Error subiendo fotos: " + err.Error()})
				return
			}
			imageURLs = uploadedURLs
		}
	}

	newPet, err := h.service.Create(services.CreatePetInput{
		Name:        form.Name,
		Type:        form.Type,
		Breed:       form.Breed,
		Age:         form.Age,
		Description: form.Description,
		Latitude:    form.Latitude,
		Longitude:   form.Longitude,
		Address:     form.Address,
		UserID:      userID,
		IsVaccinated: form.IsVaccinated,
		IsSterilized: form.IsSterilized,
		IsDewormed:   form.IsDewormed,
		SpecialNeeds: form.SpecialNeeds,
		RequiresYard: form.RequiresYard,
		GoodWithKids: form.GoodWithKids,
		GoodWithDogs: form.GoodWithDogs,
		EnergyLevel:  form.EnergyLevel,
		ImageURLs:    imageURLs,
	})

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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

// --- NUEVO HANDLER: OBTENER MIS MASCOTAS ---
func (h *PetHandler) GetMyPets(c *gin.Context) {
	userIDFloat, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
		return
	}
	
	var userID uint
	if val, ok := userIDFloat.(float64); ok {
		userID = uint(val)
	} else if val, ok := userIDFloat.(uint); ok {
		userID = val
	} else {
		userID = userIDFloat.(uint)
	}

	pets, err := h.service.GetByUserID(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error cargando mascotas: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, pets)
}

func (h *PetHandler) Search(c *gin.Context) {
	filters := SearchPetFilters{}
	if err := c.BindQuery(&filters); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Filtros inválidos"})
		return
	}
	pets, err := h.service.GetAll()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, pets)
}

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

	pets, err := h.service.GetNearby(lat, lng, dist)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error calculando cercanía: " + err.Error()})
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

	userIDVal, _ := c.Get("userID")
	var userID uint
	if val, ok := userIDVal.(float64); ok {
		userID = uint(val)
	} else if val, ok := userIDVal.(uint); ok {
		userID = val
	} else {
		userID = userIDVal.(uint)
	}

	if err := h.service.Delete(uint(id), userID); err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Mascota eliminada correctamente"})
}