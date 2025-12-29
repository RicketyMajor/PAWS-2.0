# Fase 3: Matchmaking y Geolocalización Avanzada

## Introducción

La Fase 3 implementa el corazón funcional de PAWS: un sofisticado sistema de matchmaking y búsqueda geoespacial. Esta fase introduce algoritmos de puntuación de compatibilidad y consultas SQL geoespaciales que permiten a los adoptantes encontrar mascotas cercanas que cumplan sus preferencias. La arquitectura mantiene separación de responsabilidades mediante servicios reutilizables y handlers especializados.

## Objetivos de la Fase 3

1. Implementar buscador de mascotas con filtros avanzados (tipo, raza, edad)
2. Crear algoritmo de matching que puntúa compatibilidad entre adoptantes y mascotas
3. Implementar búsqueda geoespacial usando fórmula de distancia SQL
4. Crear endpoint de búsqueda que combina filtros con geolocalización
5. Separar rutas públicas (lectura) de rutas protegidas (escritura)
6. Optimizar consultas con JOIN y WHERE clauses complejas

## Stack Tecnológico (Sin cambios)

### Backend

- **Lenguaje**: Go 1.24.0
- **Framework Web**: Gin v1.11.0
- **ORM**: GORM v1.31.1
- **Criptografía**: golang.org/x/crypto
- **JWT**: github.com/golang-jwt/jwt/v5
- **UUID**: github.com/google/uuid

### Base de Datos

- **PostgreSQL**: Versión 15 con PostGIS 3.3
- **Funciones**: acos(), radians() para cálculos de distancia

## Cambios en la Estructura del Proyecto

Comparando con Fase 2, los cambios son enfocados en búsqueda y matchmaking:

```
PAWS-2.0/
├── cmd/
│   └── api/
│       └── main.go                    # (ACTUALIZADO: Rutas reorganizadas)
├── internal/
│   ├── core/
│   │   ├── domain/
│   │   │   ├── user.go               # (Sin cambios)
│   │   │   └── pet.go                # (Sin cambios)
│   │   └── services/
│   │       ├── auth_service.go       # (Sin cambios)
│   │       ├── pet_service.go        # (ACTUALIZADO: método Search())
│   │       ├── file_service.go       # (Sin cambios)
│   │       ├── identity_service.go   # (Sin cambios)
│   │       └── match_service.go      # NUEVO: Algoritmo de matching
│   ├── transport/
│   │   └── http/
│   │       ├── auth_handler.go       # (Sin cambios)
│   │       ├── pet_handler.go        # (ACTUALIZADO: método Search())
│   │       ├── upload_handler.go     # (Sin cambios)
│   │       ├── identity_handler.go   # (Sin cambios)
│   │       ├── match_handler.go      # NUEVO: Endpoint /match
│   │       └── middleware/           # (Sin cambios)
│   └── platform/
│       └── database/                 # (Sin cambios)
├── documentation/
│   └── Fase-3.md                     # Este archivo
└── [otros archivos sin cambios]
```

## Detalles Técnicos Implementados

### 1. Servicio de Búsqueda (services/pet_service.go - método Search)

```go
func (s *PetService) Search(filters map[string]interface{}) ([]domain.Pet, error) {
    var pets []domain.Pet

    query := database.DB.Model(&domain.Pet{}).Preload("User")

    // 1. Filtro por Estado
    query = query.Where("status = ?", domain.StatusAvailable)

    // 2. Filtros de Texto
    if val, ok := filters["type"]; ok && val != "" {
        query = query.Where("type = ?", val)
    }
    if val, ok := filters["breed"]; ok && val != "" {
        query = query.Where("breed ILIKE ?", "%"+val.(string)+"%")
    }
    if maxAge, ok := filters["max_age"].(int); ok && maxAge > 0 {
        query = query.Where("age <= ?", maxAge)
    }

    // 3. Filtro Geoespacial
    if lat, okLat := filters["lat"].(float64); okLat && lat != 0 {
        if long, okLong := filters["long"].(float64); okLong && long != 0 {
            if radius, okRadius := filters["radius"].(float64); okRadius && radius > 0 {
                distanceFormula := "6371 * acos(cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + sin(radians(?)) * sin(radians(latitude)))"
                query = query.Where(distanceFormula+" < ?", lat, long, lat, radius)
            }
        }
    }

    err := query.Find(&pets).Error
    return pets, err
}
```

**Explicación Línea por Línea**:

**Parámetro `filters`**: Map flexible que permite cualquier combinación de filtros

**query := database.DB.Model(&domain.Pet{})**:

- Inicia builder GORM para la tabla Pet
- `.Model()` especifica la tabla sin hacer SELECT todavía

**Preload("User")**:

- JOIN automático: Trae datos del Usuario propietario
- Equivalente a: `SELECT pets.*, users.* FROM pets JOIN users ...`
- `json:"-"` en User evita anidar datos innecesarios

**Filtro de Estado**:

```go
query = query.Where("status = ?", domain.StatusAvailable)
```

- Parámetro con placeholder `?` previene SQL injection
- Solo retorna mascotas disponibles

**Filtro de Tipo**:

```go
query = query.Where("type = ?", val)
```

- Búsqueda exacta: "Dog" ≠ "dog"

**Filtro de Raza**:

```go
query = query.Where("breed ILIKE ?", "%"+val.(string)+"%")
```

- `ILIKE` es PostgreSQL para insensible a mayúsculas
- `"%"+val+"%"` es búsqueda LIKE con comodines
- Ejemplo: "golden" encuentra "Golden Retriever"
- Conversión `val.(string)` es type assertion (de interface{} a string)

**Filtro de Edad**:

```go
query = query.Where("age <= ?", maxAge)
```

- Encuentra mascotas menores o iguales a edad máxima

**Geofiltro - La Magia**:

```go
distanceFormula := "6371 * acos(cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + sin(radians(?)) * sin(radians(latitude)))"
query = query.Where(distanceFormula+" < ?", lat, long, lat, radius)
```

Esta es la **fórmula de Haversine simplificada** para calcular distancia entre dos puntos en la Tierra:

**Componentes**:

- `6371`: Radio de la Tierra en kilómetros
- `radians()`: Convierte grados a radianes (SQL function)
- `cos()`, `sin()`, `acos()`: Funciones trigonométricas (SQL natives)

**Fórmula**:

```
distance = R * acos(
    cos(lat1) * cos(lat2) * cos(lon2 - lon1) +
    sin(lat1) * sin(lat2)
)
```

Donde:

- `R = 6371 km` (radio Tierra)
- `lat1, lon1` = ubicación del usuario (?)
- `lat2, lon2` = latitud, longitud de la mascota (en DB)

**Ejemplo Práctico**:
Si usuario está en (-33.5, -70.5) y busca radio 10km:

```sql
SELECT * FROM pets
WHERE status = 'available'
AND 6371 * acos(
    cos(radians(-33.5)) * cos(radians(latitude)) *
    cos(radians(longitude) - radians(-70.5)) +
    sin(radians(-33.5)) * sin(radians(latitude))
) < 10
```

PostgreSQL evalúa esto nativamente, retornando solo mascotas dentro del radio.

**Performance**:

- Sin índices, esta consulta es O(n) - escanea toda tabla
- Con índice GIST en (latitude, longitude), puede usar índice geoespacial
- PostGIS proporciona tipos POINT y funciones más eficientes

### 2. DTOs del Handler (transport/http/pet_handler.go)

```go
type SearchPetFilters struct {
    Type   string  `form:"type"`
    Breed  string  `form:"breed"`
    Lat    float64 `form:"lat"`
    Long   float64 `form:"long"`
    Radius float64 `form:"radius"`
    MaxAge int     `form:"max_age"`
}
```

**Tags `form:"field"`**:

- Diferente a `json:` (que es para JSON body)
- `form:` es para parámetros URL query string
- Ejemplo: `/search?type=Dog&lat=-33.5&long=-70.5&radius=10`

**Conversión automática**:

- Gin convierte "25.5" en float64 automáticamente
- Convierte "10" en int

### 3. Handler de Búsqueda (transport/http/pet_handler.go)

```go
func (h *PetHandler) Search(c *gin.Context) {
    var filters SearchPetFilters

    if err := c.ShouldBindQuery(&filters); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "parámetros inválidos"})
        return
    }

    filterMap := map[string]interface{}{
        "type":    filters.Type,
        "breed":   filters.Breed,
        "lat":     filters.Lat,
        "long":    filters.Long,
        "radius":  filters.Radius,
        "max_age": filters.MaxAge,
    }

    pets, err := h.service.Search(filterMap)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, pets)
}
```

**ShouldBindQuery vs ShouldBindJSON**:

- `ShouldBindQuery`: Lee parámetros URL (`?key=value`)
- `ShouldBindJSON`: Lee body JSON (POST/PUT)

**Conversión a Map**:

```go
filterMap := map[string]interface{}{...}
```

Es necesario porque el servicio acepta `map[string]interface{}` para máxima flexibilidad.

**Uso**:

```bash
GET /api/v1/pets/search?type=Dog&breed=Golden&lat=-33.5&long=-70.5&radius=5&max_age=60
```

### 4. Servicio de Matching (services/match_service.go)

```go
type ScoredPet struct {
    Pet   domain.Pet `json:"pet"`
    Score int        `json:"match_score"` // 0-100
}

func (s *MatchService) FindMatches(prefType, prefBreed string, prefMaxAge int, userLat, userLon float64) ([]ScoredPet, error) {
    allPets, err := s.petService.Search(map[string]interface{}{})
    if err != nil {
        return nil, err
    }

    var matches []ScoredPet

    for _, pet := range allPets {
        score := 0

        // A. Tipo (40 puntos)
        if pet.Type == prefType {
            score += 40
        } else {
            continue // Tipo crítico, sin tipo correcto no hay match
        }

        // B. Raza (20 puntos)
        if prefBreed != "" && pet.Breed == prefBreed {
            score += 20
        }

        // C. Edad (20 puntos)
        if prefMaxAge > 0 && pet.Age <= prefMaxAge {
            score += 20
        }

        // D. Proximidad (20 puntos)
        if pet.Latitude != 0 && pet.Longitude != 0 {
            score += 20
        }

        if score > 0 {
            matches = append(matches, ScoredPet{Pet: pet, Score: score})
        }
    }

    return matches, nil
}
```

**Algoritmo de Puntuación**:

| Factor          | Puntos  | Descripción                  |
| --------------- | ------- | ---------------------------- |
| Tipo Correcto   | 40      | Crítico (si falla, continue) |
| Raza Coincide   | 20      | Deseable pero opcional       |
| Edad Aceptable  | 20      | Si está dentro de rango      |
| Tiene Ubicación | 20      | Mascota real con coordenadas |
| **Total**       | **100** | Score máximo                 |

**Logística**:

1. `NewMatchService(petService)`: Inyecta petService
2. `FindMatches()`: Toma preferencias del adoptante
3. Obtiene TODAS las mascotas via `petService.Search({})`
4. Para cada mascota, calcula score según criterios
5. Solo agrega al resultado si score > 0

**Puntuación en Memoria vs Base de Datos**:

- **Ventaja**: Lógica flexible, fácil de testear
- **Desventaja**: O(n) en memoria, no escala bien
- **Mejora Futura**: Mover lógica a SQL para queries O(1)

### 5. Handler de Matching (transport/http/match_handler.go)

```go
func (h *MatchHandler) GetMatches(c *gin.Context) {
    // Leer preferencias de URL
    prefType := c.Query("type")
    prefBreed := c.Query("breed")

    ageStr := c.Query("max_age")
    maxAge, _ := strconv.Atoi(ageStr)

    // Llamar servicio
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
```

**Diferencia con Search**:

- Search: Filtros complejos + geolocalización (en BD)
- GetMatches: Puntuación de compatibilidad (en memoria)

**Uso**:

```bash
GET /api/v1/pets/match?type=Dog&breed=Golden&max_age=60
```

### 6. Reorganización de Rutas (main.go)

**Antes (Fase 2)**:

```go
api := r.Group("/api/v1")
{
    pets := api.Group("/pets")
    pets.Use(middleware.AuthMiddleware())
    {
        pets.POST("", petHandler.Create)
        pets.GET("", petHandler.GetAll)
    }
}
```

**Ahora (Fase 3)**:

```go
api := r.Group("/api/v1")
{
    // Público
    petsPublic := api.Group("/pets")
    {
        petsPublic.GET("/search", petHandler.Search)  // Con filtros
        petsPublic.GET("/match", matchHandler.GetMatches)
        petsPublic.GET("", petHandler.GetAll)
    }

    // Protegido
    petsProtected := api.Group("/pets")
    petsProtected.Use(middleware.AuthMiddleware())
    {
        petsProtected.POST("", petHandler.Create)
    }
}
```

**Ventajas**:

- GET sin autenticación: Adoptantes ven mascotas sin registrarse
- POST con autenticación: Solo rescatistas verificados pueden publicar
- Búsqueda avanzada accesible públicamente

**Problema Resuelto**: Mismo prefijo `/pets` pero grupos diferentes

- Sin middleware: `petsPublic.GET()` accesible
- Con middleware: `petsProtected.POST()` requiere token

### 7. Flujo de Consulta Geoespacial

```
Cliente solicita:
GET /api/v1/pets/search?type=Dog&lat=-33.5&long=-70.5&radius=10

↓

PetHandler.Search():
1. ParseaQuery ← SearchPetFilters
2. Convierte a Map
3. Llama PetService.Search(filterMap)

↓

PetService.Search():
1. Inicia query GORM
2. Aplica filtros WHERE
3. Aplica fórmula de distancia WHERE
4. Ejecuta query SQL

↓

PostgreSQL:
SELECT pets.* FROM pets
WHERE status = 'available'
  AND type = 'Dog'
  AND 6371 * acos(...) < 10

↓

Retorna []Pet ← Handler ← Cliente

Response:
{
  "matches_found": 3,
  "results": [
    {
      "id": 1,
      "name": "Max",
      "type": "Dog",
      ...
    },
    ...
  ]
}
```

## Comparación Search vs Match vs GetAll

| Endpoint         | Autenticación | Filtros               | Búsqueda   | Puntuación |
| ---------------- | ------------- | --------------------- | ---------- | ---------- |
| GET /pets        | No            | Ninguno               | Todas (BD) | No         |
| GET /pets/search | No            | Type, Breed, Age, Geo | SQL (BD)   | No         |
| GET /pets/match  | No            | Type, Breed, Age      | Memoria    | Sí (0-100) |

**Uso por Caso**:

- **GetAll**: Listar todas (página inicial)
- **Search**: "Buscar perros Golden dentro de 5km"
- **Match**: "¿Qué puntuación tienen según mis preferencias?"

## Cambios Detectados desde Fase 2

| Componente           | Cambio                | Impacto                           |
| -------------------- | --------------------- | --------------------------------- |
| **pet_service.go**   | Nuevo método Search() | Búsqueda con filtros SQL          |
| **match_service.go** | Archivo nuevo         | Algoritmo de scoring              |
| **match_handler.go** | Archivo nuevo         | Endpoint /match                   |
| **pet_handler.go**   | Nuevo método Search() | Endpoint /search                  |
| **main.go**          | Rutas reorganizadas   | Separación público/protegido      |
| **Rutas**            | 3 nuevos endpoints    | Búsqueda, match, mejor estructura |

## Consultas SQL Generadas

### Ejemplo 1: Búsqueda Simple

```bash
GET /pets?type=Dog
```

SQL Generado:

```sql
SELECT * FROM pets
WHERE status = 'available'
  AND type = 'Dog'
```

### Ejemplo 2: Búsqueda Geoespacial

```bash
GET /pets/search?type=Dog&lat=-33.5&long=-70.5&radius=5
```

SQL Generado:

```sql
SELECT * FROM pets
WHERE status = 'available'
  AND type = 'Dog'
  AND 6371 * acos(
    cos(radians(-33.5)) * cos(radians(latitude)) *
    cos(radians(longitude) - radians(-70.5)) +
    sin(radians(-33.5)) * sin(radians(latitude))
  ) < 5
```

### Ejemplo 3: Búsqueda Compleja

```bash
GET /pets/search?type=Dog&breed=Golden&max_age=60&lat=-33.5&long=-70.5&radius=10
```

SQL Generado:

```sql
SELECT * FROM pets
WHERE status = 'available'
  AND type = 'Dog'
  AND breed ILIKE '%Golden%'
  AND age <= 60
  AND 6371 * acos(
    cos(radians(-33.5)) * cos(radians(latitude)) *
    cos(radians(longitude) - radians(-70.5)) +
    sin(radians(-33.5)) * sin(radians(latitude))
  ) < 10
```

## Decisiones Arquitectónicas

### 1. Matching en Memoria vs BD

**Actual (Fase 3)**: En memoria

- MatchService obtiene todos pets
- Puntúa en aplicación
- Retorna ScoredPet[]

**Problemas**:

- No escala (Si 10k mascotas, 10k loops)
- Lento sin índices

**Mejora Futura (Fase 4+)**:

```go
// Mover scoring a SQL
SELECT pets.*,
  (CASE WHEN type = ? THEN 40 ELSE 0 END +
   CASE WHEN breed = ? THEN 20 ELSE 0 END +
   ... ) AS score
FROM pets
WHERE score > 0
ORDER BY score DESC
LIMIT 20
```

### 2. Fórmula de Haversine Simplificada

Usamos fórmula simple por:

- Compatible con PostgreSQL vanilla (sin PostGIS)
- Suficiente precisión para ciudades
- Rápida de calcular

**Precisión**:

- Dentro de 10km: ±1m error
- Dentro de 100km: ±10m error
- Para ciudades: Totalmente aceptable

**Limitación**: Tierra esférica perfecta (en realidad es ovoide)

**Alternativa Exacta** (Fase 6 con PostGIS):

```sql
SELECT * FROM pets
WHERE ST_DWithin(
  ST_MakePoint(longitude, latitude)::geography,
  ST_MakePoint(?, ?)::geography,
  ? * 1000  -- Convertir km a metros
)
```

### 3. Type Filtering Crítico

```go
if pet.Type == prefType {
    score += 40
} else {
    continue  // Skip completamente
}
```

**Reasoning**:

- No tiene sentido un perro si buscas gato
- Evita resultados inútiles
- 40 puntos = 40% de score total (mayor peso)

### 4. Parámetros Query vs Body

**Search**: Query string

```bash
GET /pets/search?type=Dog&lat=-33.5
```

**Reasoning**:

- HTTP best practice: GET con query
- Cacheability en CDN
- Bookmarkeable
- Idempotent

### 5. Separación de Rutas

**Públicas**:

```
GET /pets/search
GET /pets/match
GET /pets
```

**Protegidas**:

```
POST /pets/create
```

**Ventaja**:

- Adoptantes ven catálogo sin registrarse
- Rescatistas deben verificarse para publicar
- Balance entre experiencia y seguridad

## Implementación de Reglas de Seguridad

### R-SEC-01: Verificación (Preparado)

Futuro: Solo usuarios verificados pueden ver mascotas de ciertos rescatistas:

```go
if !user.IsVerified && pet.User.IsVerified {
    // Skip o marcar como "Requiere Verificación"
}
```

### R-SEC-02: Multicuentas

Sin cambios desde Fase 1.

### R-SEC-03: Blacklist

Futuro: Excluir mascotas de usuarios baneados:

```go
query = query.Where("user_id NOT IN (SELECT id FROM users WHERE is_banned = true)")
```

## Stack de Dependencias (Sin cambios)

Igual que Fase 2. PostgreSQL native functions suficientes para geolocalización básica.

## COMPLETADO EN ETAPA 5: Geolocalización Real con Haversine

### Enhancements Implementados

La Etapa 5 mejoró significativamente la implementación de geolocalización de Fase 3, evolucionando de búsquedas genéricas a búsquedas precisas con distancia real en kilómetros:

#### 1. Método SearchNearby en PetService

**Nueva implementación** (superior a la búsqueda de Fase 3):

```go
func (s *PetService) SearchNearby(lat, lng float64, distanceKM float64) ([]domain.Pet, error) {
	var pets []domain.Pet

	// Fórmula Haversine en SQL puro para distancia geodésica
	query := `
		SELECT *,
		(6371 * acos(
			cos(radians(?)) * cos(radians(latitude)) *
			cos(radians(longitude) - radians(?)) +
			sin(radians(?)) * sin(radians(latitude))
		)) AS distance
		FROM pets
		WHERE status = 'available'
		ORDER BY distance ASC
	`

	result := s.db.Raw(query, lat, lng, lat).Scan(&pets)

	// Filtrado post-query por distancia
	var filtered []domain.Pet
	for _, pet := range pets {
		if pet.Distance <= distanceKM {
			filtered = append(filtered, pet)
		}
	}

	return filtered, result.Error
}
```

**Diferencias vs Fase 3**:

- Fase 3: Busca mascotas con radio genérico, sin cálculo explícito de distancia
- Etapa 5: Calcula distancia geodésica real de CADA mascota, la retorna, y filtra por km específicos
- Fase 3: Usa parámetro "radius" (unidad indefinida)
- Etapa 5: Especifica distancia en km, retorna pets ordenadas por proximidad

#### 2. Endpoint GET /pets/nearby (Handler)

**Nueva ruta pública** en PetHandler:

```go
func (h *PetHandler) GetNearby(c *gin.Context) {
	latStr := c.DefaultQuery("lat", "0")
	lngStr := c.DefaultQuery("lng", "0")
	distStr := c.DefaultQuery("dist", "10") // 10km por defecto

	lat, _ := strconv.ParseFloat(latStr, 64)
	lng, _ := strconv.ParseFloat(lngStr, 64)
	dist, _ := strconv.ParseFloat(distStr, 64)

	pets, err := h.petService.SearchNearby(lat, lng, dist)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"pets": pets,
		"count": len(pets),
		"radius_km": dist,
	})
}
```

**Ruta registrada** en main.go:

```go
petsPublic.GET("/nearby", petHandler.GetNearby)
```

**Ventajas sobre Fase 3**:

- Retorna distancia calculada en respuesta JSON
- Adopters ven claramente cuán lejos está cada mascota
- Endpoint público sin requerir autenticación
- Parámetro "dist" opcional (default 10km)

#### 3. Algoritmo Haversine: Desglose Matemático

La fórmula implementada en SQL:

```
distance = 6371 * acos(
    cos(radians(userLat)) * cos(radians(petLat)) * cos(radians(petLon - userLon)) +
    sin(radians(userLat)) * sin(radians(petLat))
)
```

**5 pasos de cálculo**:

1. **radians(userLat)**: Convierte latitud del usuario a radianes
2. **cos(radians(userLat)) \* cos(radians(petLat))**: Producto de cosenos de latitudes
3. **cos(radians(petLon - userLon))**: Coseno de diferencia de longitudes
4. **sin(radians(userLat)) \* sin(radians(petLat))**: Producto de senos de latitudes
5. **6371 \* acos(suma)**: Multiplica resultado por radio terrestre (6371 km)

**Resultado**: Distancia en kilómetros entre dos puntos en la Tierra

**Ventaja sobre distancia euclidiana**:

- Euclidiana: `sqrt((lat2-lat1)² + (lon2-lon1)²)` es incorrecta para la Tierra (es plana)
- Haversine: Considera la curvatura de la Tierra, es geodésica

#### 4. Integración Frontend con Permisos GPS

La Etapa 5 agregó flujo de permisos nativo en `pets_bloc.dart`:

```dart
// En LoadSwipeDeck event
if (await Geolocator.isLocationServiceEnabled()) {
	LocationPermission permission = await Geolocator.checkPermission();

	if (permission == LocationPermission.denied) {
		permission = await Geolocator.requestPermission();
	}

	if (permission == LocationPermission.whileInUse ||
	    permission == LocationPermission.always) {
		Position position = await Geolocator.getCurrentPosition(
			timeLimit: Duration(seconds: 5)
		);

		final pets = await repository.getSwipeDeck(
			lat: position.latitude,
			lon: position.longitude
		);
	}
}
```

**Comportamiento**:

- Si usuario acepta GPS: Obtiene mascotas cercanas (10-50km por defecto)
- Si usuario rechaza: App funciona igual, ve "todas" las mascotas (sin filtro de distancia)
- Si GPS desactivado en OS: Se salta sin romper la app
- Timeout de 5 segundos previene bloqueos

**Comparación vs Fase 3**:

- Fase 3: Asume coordenadas disponibles, no maneja permisos
- Etapa 5: Flujo completo de permisos, graceful fallback

#### 5. Casos de Uso Mejorados

**Caso 1: Adopter Buscando Gatos Cercanos**

- Antes (Fase 3): Abre app, ve todos los gatos, asume que están "cerca"
- Después (Etapa 5): Acepta GPS, ve solo gatos dentro de 10km, distancia visible

**Caso 2: Rescatista Rastreando Mascotas Perdidas**

- Antes (Fase 3): Publica coordenadas, adopters filtran manualmente por área
- Después (Etapa 5): SearchNearby retorna mascotas ordenadas por proximidad, rescatista ve impacto inmediato

**Caso 3: Adopter sin GPS**

- Antes (Fase 3): Endpoint requiere coordenadas, falla si no tiene GPS
- Después (Etapa 5): Endpoint funciona sin coords, retorna todas, adopter puede filtrar manualmente

#### 6. Impacto en Eficiencia

**Reducción de Datos**:

- Buscar en radio de 50km reduce candidatos de 10,000+ (todas mascotas) a 50-100
- Menos datos transmitidos (50 mascotas vs 10,000)
- Menor uso de batería (filtrado en servidor, no en cliente)

**Mejora en UX**:

- Adopter ve solo opciones realistas (puede viajar)
- Mascota relevante está arriba de la lista (cercana)
- Puede expandir radio si necesita (parámetro "dist")

## Referencias

- Haversine Formula: https://en.wikipedia.org/wiki/Haversine_formula
- PostgreSQL Math Functions: https://www.postgresql.org/docs/current/functions-math.html
- GORM Query: https://gorm.io/docs/query.html
- Gin Query Binding: https://gin-gonic.com/docs/examples/binding-query-string/
- Geospatial SQL Patterns: https://postgis.net/docs/
