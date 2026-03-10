// Package http contains the HTTP handlers for the application.
package http

import (
	"net/http"
	"strconv"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/gin-gonic/gin"
)

// =========================================================================
// Request & Response Structures
// =========================================================================

// SearchPetFilters defines the query parameters for searching pets.
type SearchPetFilters struct {
	Type   string  `form:"type"`
	Breed  string  `form:"breed"`
	Lat    float64 `form:"lat"`
	Long   float64 `form:"long"`
	Radius float64 `form:"radius"`
	MaxAge int     `form:"max_age"`
}

// CreatePetForm defines the multipart form for creating a new pet.
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

// =========================================================================
// Handler Definition
// =========================================================================

// PetHandler handles pet-related HTTP requests.
type PetHandler struct {
	service     *services.PetService
	fileService *services.FileService
}

// NewPetHandler creates a new PetHandler.
func NewPetHandler(service *services.PetService, fileService *services.FileService) *PetHandler {
	return &PetHandler{
		service:     service,
		fileService: fileService,
	}
}

// =========================================================================
// Handler Methods
// =========================================================================

// Create handles the creation of a new pet with multiple image uploads.
func (h *PetHandler) Create(c *gin.Context) {
	userIDFloat, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	
	var userID uint
	if val, ok := userIDFloat.(float64); ok {
		userID = uint(val)
	} else if val, ok := userIDFloat.(uint); ok {
		userID = val
	} else {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format"})
		return
	}

	var form CreatePetForm
	if err := c.ShouldBind(&form); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid form data: " + err.Error()})
		return
	}

	formMultipart, err := c.MultipartForm()
	var imageURLs []string

	if err == nil {
		files := formMultipart.File["images"]
		if len(files) > 0 {
			if len(files) > 10 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Maximum of 10 photos allowed"})
				return
			}
			uploadedURLs, err := h.fileService.SaveMultipleImages(c.Request.Context(), files)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Error uploading photos: " + err.Error()})
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

// GetAll retrieves all pets.
func (h *PetHandler) GetAll(c *gin.Context) {
	pets, err := h.service.GetAll()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, pets)
}

// GetMyPets retrieves all pets owned by the authenticated user.
func (h *PetHandler) GetMyPets(c *gin.Context) {
	userIDFloat, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	
	var userID uint
	if val, ok := userIDFloat.(float64); ok {
		userID = uint(val)
	} else if val, ok := userIDFloat.(uint); ok {
		userID = val
	} else {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format"})
		return
	}

	pets, err := h.service.GetByUserID(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error loading pets: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, pets)
}

// Search handles searching for pets based on filters.
// Note: Currently returns all pets, filters are not implemented in the service.
func (h *PetHandler) Search(c *gin.Context) {
	filters := SearchPetFilters{}
	if err := c.BindQuery(&filters); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid filters"})
		return
	}
	pets, err := h.service.GetAll() // TODO: Implement filtering in service layer
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, pets)
}

// GetNearby retrieves pets within a certain distance of a location.
func (h *PetHandler) GetNearby(c *gin.Context) {
	latStr := c.Query("lat")
	lngStr := c.Query("lng")
	distStr := c.Query("dist")

	if latStr == "" || lngStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Latitude and Longitude are required"})
		return
	}

	lat, _ := strconv.ParseFloat(latStr, 64)
	lng, _ := strconv.ParseFloat(lngStr, 64)
	dist, _ := strconv.ParseFloat(distStr, 64)

	if dist == 0 {
		dist = 10.0 // Default distance in km
	}

	pets, err := h.service.GetNearby(lat, lng, dist)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error calculating nearby pets: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, pets)
}

// GetPetByID retrieves a single pet by its ID.
func (h *PetHandler) GetPetByID(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID"})
		return
	}

	pet, err := h.service.GetByID(uint(id))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Pet not found"})
		return
	}

	c.JSON(http.StatusOK, pet)
}

// Delete handles the deletion of a pet.
func (h *PetHandler) Delete(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID"})
		return
	}

	userIDVal, _ := c.Get("userID")
	var userID uint
	if val, ok := userIDVal.(float64); ok {
		userID = uint(val)
	} else if val, ok := userIDVal.(uint); ok {
		userID = val
	} else {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format"})
		return
	}

	if err := h.service.Delete(uint(id), userID); err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Pet deleted successfully"})
}