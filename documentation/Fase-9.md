# Fase 9: Matchmaking Inteligente y Perfiles Enriquecidos

## Introducción

**ACTUALIZACIÓN - IMPLEMENTACIÓN ACTUAL (Etapa 2)**: Esta Fase 9 describe la arquitectura de matchmaking cuyo core ha sido completamente implementado en Etapa 2. Mientras que esta documentación fue concebida como especulativa, la mayoría de sus objetivos fundamentales están ahora en producción. Ver sección "Estado de Implementación" abajo.

La Fase 9 es el punto de inflexión donde PAWS deja de ser una plataforma de listados simples y se transforma en un **motor de compatibilidad inteligente**. Esta fase implementa el corazón del valor propuesto de PAWS: conectar a los adoptantes adecuados con las mascotas adecuadas basándose en compatibilidad real.

Transformamos el modelo de "usuario ve todos los animales" al modelo de "servidor sugiere mascotas compatibles". El algoritmo utiliza restricciones duras (hard constraints) sobre las preferencias y capacidades del adoptante, y de los requisitos de cada mascota, para presentar únicamente candidatos viables.

Esta es la fase que diferencia una plataforma de transacciones de una plataforma de experiencias: en lugar de esperar que el usuario encuentre a la mascota perfecta, le entregamos un deck curado de candidatos con alta probabilidad de éxito.

## Estado de Implementación

### ✓ COMPLETADO EN ETAPA 2

Los siguientes componentes están **completamente implementados y en producción**:

- ✓ Sistema de perfiles enriquecidos (UserProfile con 7 campos demográficos)
- ✓ Extensión de modelos de mascotas (5 campos de compatibilidad)
- ✓ Algoritmo GetSwipeDeck con 3 filtros AND hard constraints
- ✓ Flujo de swipe (Like/Dislike) con estado PENDING/REJECTED
- ✓ Flujo de respuesta del rescatista (Accept/Reject)
- ✓ Tabla Match con gestión de interacciones
- ✓ UserService y MatchService completamente funcionales
- ✓ UserHandler y MatchHandler con todos los endpoints
- ✓ Protección JWT en todas las rutas protegidas
- ✓ Fallback inteligente para usuarios sin perfil (mostrar todas mascotas)

**Ubicación del código actual**:

- `internal/core/domain/user_profile.go`
- `internal/core/services/user_service.go`
- `internal/core/services/match_service.go`
- `internal/transport/http/user_handler.go`
- `internal/transport/http/match_handler.go`
- Extensiones en `internal/core/domain/pet.go` y `cmd/api/main.go`

### ✓ COMPLETADO EN ETAPA 4 - Bandejas Inteligentes y Robustez

Los siguientes componentes fueron mejorados y completados en Etapa 4 para proporcionar una experiencia de usuario superior:

- ✓ GetSwipeDeck refactorizado con SQL puro LEFT JOIN para eliminar duplicados
- ✓ GetAdopterPendingMatches: Endpoint para "Mis Likes Pendientes" del adoptante
- ✓ GetAcceptedMatches mejorado: Chats activos del adoptante con datos del rescatista
- ✓ GetPendingRequests: Centro de control rescatista para solicitudes entrantes
- ✓ GetRescuerMatches: Chats activos del rescatista
- ✓ Nuevos endpoints HTTP: /matches/mine, /matches/mine/pending, /matches/rescuer
- ✓ Helper function getUserIDFromContext: Type-safe JWT handling (maneja float64, uint, int, uint64)
- ✓ ChatBloc mejorado: JWT decoding local para identificar mensajes propios
- ✓ ChatScreen robusta: Manejo de listas vacías, reverse scroll, burbujas diferenciadas
- ✓ Correcciones críticas: Estabilidad frontend, type casting seguro, SQL LEFT JOIN

**Ubicación del código mejorado**:

- `internal/core/services/match_service.go` (refactorizado con LEFT JOIN y nuevos métodos)
- `internal/transport/http/match_handler.go` (nuevos endpoints y helper function)
- `app/lib/features/chat/presentation/bloc/chat_bloc.dart` (JWT decoding)
- `app/lib/features/chat/presentation/screens/chat_screen.dart` (manejo robusto de listas)

### ⏳ DISEÑADO PARA FUTURO

Estos componentes están diseñados en la arquitectura pero **NO están implementados aún**:

- ⏳ Scoring de compatibilidad (compatibilidad numérica 0-100)
- ⏳ Machine Learning para recomendaciones
- ⏳ Filtros dinámicos del lado del cliente
- ⏳ Análisis de comportamiento de matching
- ⏳ Refine iterativo basado en datos

La arquitectura actual soporta estas extensiones sin cambios disruptivos (endpoints pueden retornar scores adicionales sin breaking changes).

## Objetivos de la Fase 9

1. ✓ Implementar sistema de perfiles enriquecidos para usuarios adoptantes → **COMPLETADO en Etapa 2**
2. ✓ Extender modelos de mascotas con requisitos de compatibilidad → **COMPLETADO en Etapa 2**
3. ✓ Crear algoritmo inteligente de filtrado (GetSwipeDeck) → **COMPLETADO en Etapa 2, mejorado en Etapa 4**
4. ✓ Implementar flujo de swipe (Like/Dislike) con estado Pending → **COMPLETADO en Etapa 2**
5. ✓ Implementar flujo de respuesta del rescatista (Accept/Reject) → **COMPLETADO en Etapa 2**
6. ✓ Crear tabla y servicios para gestionar Matches → **COMPLETADO en Etapa 2, con bandejas inteligentes en Etapa 4**
7. ✓ Establecer arquitectura de compatibilidad para futuras mejoras → **COMPLETADO en Etapa 2**
8. ✓ Documentar flujos de matchmaking y experiencia de usuario → **COMPLETADO en Etapa 2, con bandejas en Etapa 4**

## Stack Tecnológico - Matchmaking

### Base de Datos

- **Tabla UserProfile**: Perfil sociodemográfico del adoptante

  - Housing type (Casa, Departamento, Parcela)
  - Tiene patio
  - Tiene niños
  - Tiene otras mascotas
  - Experiencia (Principiante, Intermedio, Experto)
  - Tiempo disponible (Bajo, Medio, Alto)

- **Tabla Pet (Extendida)**: Requisitos y características de mascota

  - Requiere patio (hard constraint)
  - Bueno con niños
  - Bueno con perros
  - Bueno con gatos
  - Nivel de energía

- **Tabla Match**: Registro de interacciones con estados (Etapa 4)
  - Adopter ID, Pet ID
  - Estado (Pending, Accepted, Rejected)
  - Timestamp de creación/actualización
  - Utilizado para Bandejas Inteligentes en Etapa 4

### Servicios

- **UserService**: Gestión de perfiles demográficos
- **MatchService**: Algoritmo de filtrado e interacciones (mejorado Etapa 4 con LEFT JOIN y bandejas)
- **PetService**: Datos de mascotas (ampliado)
- **ChatService** (Etapa 3): Persistencia y validación de mensajes (usado por bandejas de Etapa 4)

### Handlers

- **UserHandler**: Endpoints para actualizar perfil y obtener candidatos
- **MatchHandler**: Endpoints para swipe, solicitudes pendientes, respuestas, y bandejas (Etapa 4)
- **ChatBloc** (Flutter): Gestión de estado de chat con JWT decoding (Etapa 4)

## Cambios en la Estructura del Proyecto

### Nuevos Archivos Creados

#### 1. domain/user_profile.go

Modelo que representa la información sociodemográfica del adoptante:

```go
type HousingType string

const (
    HousingHouse     HousingType = "house"
    HousingApartment HousingType = "apartment"
    HousingParcel    HousingType = "parcel"
)

type UserProfile struct {
    ID            uint           `gorm:"primaryKey"`
    UserID        uint           `gorm:"uniqueIndex;not null"` // FK a User
    Housing       HousingType    // Casa, Depto, Parcela
    HasYard       bool           // ¿Tiene patio?
    HasChildren   bool           // ¿Tiene niños?
    HasOtherPets  bool           // ¿Tiene otras mascotas?
    Experience    string         // beginner, intermediate, expert
    TimeAvailable string         // low, medium, high
    CreatedAt     time.Time
    UpdatedAt     time.Time
}
```

**Propósito**: Almacenar una sola instancia de preferencias/capacidades por usuario (relación 1-a-1 con User).

#### 2. domain/match.go

Modelo que representa un Like/Dislike y su evolución:

```go
type MatchStatus string

const (
    MatchPending  MatchStatus = "pending"  // Like dado, esperando respuesta
    MatchAccepted MatchStatus = "accepted" // Rescatista aceptó
    MatchRejected MatchStatus = "rejected" // Rescatista rechazó
)

type Match struct {
    ID        uint        `gorm:"primaryKey"`
    AdopterID uint        `gorm:"index;not null"` // Quién dio el Like
    Adopter   User        `gorm:"foreignKey:AdopterID"`
    PetID     uint        `gorm:"index;not null"` // A quién dio Like
    Pet       Pet         `gorm:"foreignKey:PetID"`
    Status    MatchStatus `gorm:"type:varchar(20);default:'pending'"`
    Message   string      // "Me encantó tu perro porque..."
    CreatedAt time.Time
    UpdatedAt time.Time
}
```

**Propósito**: Rastrear todas las interacciones (swipes) entre usuarios y mascotas, permitiendo que rescatistas respondan.

#### 3. services/user_service.go

Servicio para gestionar perfiles de usuario:

```go
type UserService struct {
    db *gorm.DB
}

// CreateOrUpdateProfile guarda información demográfica
func (s *UserService) CreateOrUpdateProfile(userID uint, profile domain.UserProfile) error {
    // Upsert: actualiza si existe, crea si no
}

// GetProfile obtiene el perfil para el algoritmo
func (s *UserService) GetProfile(userID uint) (*domain.UserProfile, error) {
}
```

**Responsabilidades**:

- Crear/actualizar perfil del adoptante
- Recuperar perfil para consultas de compatibilidad

#### 4. services/match_service.go

Corazón del algoritmo de matchmaking:

```go
type MatchService struct {
    db         *gorm.DB
    petService *PetService
}

// GetSwipeDeck: Retorna candidatos filtrados para un usuario
func (s *MatchService) GetSwipeDeck(userID uint) ([]domain.Pet, error) {
    // 1. Obtener perfil del usuario
    // 2. Query base: Mascotas disponibles
    // 3. Exclusión: Mascotas con las que ya interactuó
    // 4. Filtros inteligentes: Hard constraints
    // 5. Ejecutar y retornar
}

// Swipe: Registra Like/Dislike
func (s *MatchService) Swipe(adopterID, petID uint, isLike bool) error {
}

// GetPendingRequests: Solicitudes pendientes para rescatista
func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
}

// RespondMatch: Rescatista acepta/rechaza
func (s *MatchService) RespondMatch(rescuerID, matchID uint, accept bool) error {
}
```

**Flujo de GetSwipeDeck** (El Algoritmo Inteligente):

```
┌──────────────────────────────────────────────────────────────────┐
│ Adoptante solicita candidatos (GET /matches/candidates)         │
└────────────────┬─────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────┐
│ GetSwipeDeck(userID)                                             │
└────────────────┬─────────────────────────────────────────────────┘
                 │
    Step 1: Obtener UserProfile
                 │
                 ▼
    ┌──────────────────────────┐
    │ Housing: "apartment"     │
    │ HasYard: false           │
    │ HasChildren: true        │
    │ HasOtherPets: false      │
    │ Experience: "beginner"   │
    │ TimeAvailable: "high"    │
    └────────────┬─────────────┘
                 │
    Step 2: Query Base
                 │
                 ▼
    SELECT * FROM pets WHERE status = 'available'
    ┌────────────────────────────────────┐
    │ 10 mascotas encontradas            │
    └────────────┬──────────────────────┘
                 │
    Step 3: Excluir ya vistos
                 │
                 ▼
    SELECT pet_id FROM matches
    WHERE adopter_id = userID
    ┌────────────────────────────────────┐
    │ Exclude: IDs [5, 7, 12]            │
    │ Quedan: 7 mascotas                 │
    └────────────┬──────────────────────┘
                 │
    Step 4: Aplicar Filtros Inteligentes
                 │
                 ├─ Housing Filter
                 │  IF Housing = "apartment" THEN
                 │    Excluir mascotas que requires_yard = true
                 │  (Si vive en depto, no puede tener perro que necesite patio)
                 │
                 ├─ Kids Filter
                 │  IF HasChildren = true THEN
                 │    Excluir mascotas que good_with_kids = false
                 │  (Si tiene niños, la mascota DEBE ser amigable con niños)
                 │
                 ├─ Pets Filter
                 │  IF HasOtherPets = true THEN
                 │    Excluir mascotas que good_with_dogs = false
                 │  (Si tiene otras mascotas, debe ser sociable)
                 │
                 ▼
    ┌────────────────────────────────────┐
    │ Final: 4 mascotas compatibles      │
    └────────────┬──────────────────────┘
                 │
    Step 5: Retornar
                 │
                 ▼
[
    { ID: 2, Name: "Max", Type: "dog", ... },
    { ID: 8, Name: "Luna", Type: "dog", ... },
    { ID: 10, Name: "Milo", Type: "cat", ... },
    { ID: 15, Name: "Bella", Type: "dog", ... }
]
```

#### 5. handlers/user_handler.go

Endpoints para gestionar perfil e interacciones:

```go
// PUT /api/v1/profile
func (h *UserHandler) UpdateProfile(c *gin.Context) {
    // Actualizar información demográfica
}

// GET /api/v1/matches/candidates
func (h *UserHandler) GetSwipeDeck(c *gin.Context) {
    // Obtener mascotas compatibles
}
```

#### 6. handlers/match_handler.go

Endpoints para el flujo de matchmaking:

```go
// GET /api/v1/pets/match (Candidatos - redenominado)
func (h *MatchHandler) GetMatches(c *gin.Context) {
}

// POST /api/v1/matches/swipe
func (h *MatchHandler) Swipe(c *gin.Context) {
    // { pet_id: 123, is_like: true }
}

// GET /api/v1/matches/requests (Para rescatista)
func (h *MatchHandler) GetPending(c *gin.Context) {
    // Ver qué adoptantes dieron Like a mis mascotas
}

// POST /api/v1/matches/respond (Para rescatista)
func (h *MatchHandler) Respond(c *gin.Context) {
    // { match_id: 456, accept: true }
}
```

### Archivos Modificados

#### domain/pet.go (Extendido)

Se agregaron campos de compatibilidad:

```go
type Pet struct {
    // Campos existentes...
    ID          uint
    Name        string
    Type        string
    Breed       string
    Latitude    float64
    Longitude   float64
    Gender      string
    Age         int
    Status      PetStatus
    Description string

    // CAMPOS NUEVOS (Matchmaking)
    RequiresYard    bool   // Hard constraint
    GoodWithKids    bool   // ¿Amigable con niños?
    GoodWithDogs    bool   // ¿Sociable con otros perros?
    GoodWithCats    bool   // ¿Sociable con gatos?
    EnergyLevel     string // low, medium, high

    UserID    uint
    CreatedAt time.Time
    UpdatedAt time.Time
}
```

#### cmd/api/main.go (Actualizado)

Se integran nuevos servicios y handlers:

```go
// Nuevos servicios
userService := services.NewUserService(database.DB)
matchService := services.NewMatchService(database.DB, petService)

// Nuevos handlers
userHandler := httpTransport.NewUserHandler(userService, matchService)
matchHandler := httpTransport.NewMatchHandler(matchService)

// Nuevas rutas protegidas
protected.PUT("/profile", userHandler.UpdateProfile)
protected.POST("/matches/swipe", matchHandler.Swipe)
protected.GET("/matches/requests", matchHandler.GetPending)
protected.POST("/matches/respond", matchHandler.Respond)
```

## Flujo de Matchmaking Completo

### Escenario Completo: De Perfil a Adopción

```
┌─────────────────────────────────────────────────────────────────────┐
│ JUAN (Adoptante) se registra                                        │
└────────────────┬────────────────────────────────────────────────────┘
                 │
                 ▼
1. PUT /api/v1/profile
┌─────────────────────────────────────────────────────────────────────┐
│ {                                                                   │
│   "housing": "apartment",      # Vive en depto                      │
│   "has_yard": false,           # Sin patio                          │
│   "has_children": true,        # Tiene niños                        │
│   "has_other_pets": false,     # Sin otras mascotas                 │
│   "experience": "beginner",    # Principiante                       │
│   "time_available": "high"     # Mucho tiempo disponible            │
│ }                                                                   │
│                                                                     │
│ UserService.CreateOrUpdateProfile(juanID, profile)                │
│   ✓ Guardado en BD                                                 │
└─────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
2. GET /api/v1/matches/candidates
┌─────────────────────────────────────────────────────────────────────┐
│ MatchService.GetSwipeDeck(juanID)                                   │
│   1. GetProfile(juanID) -> apartment, no_yard, has_kids             │
│   2. Query: SELECT * FROM pets WHERE status = 'available'          │
│   3. Exclude: (Aún no ha visto ninguno)                             │
│   4. Filter:                                                        │
│      - RequiresYard = true? -> EXCLUIR (Juan sin patio)             │
│      - GoodWithKids = false? -> EXCLUIR (Juan tiene niños)          │
│   5. Result: 3 candidatos                                           │
│                                                                     │
│ Response: [                                                         │
│   { id: 1, name: "Max", type: "dog", energy: "medium", ... },      │
│   { id: 5, name: "Luna", type: "dog", energy: "high", ... },       │
│   { id: 8, name: "Milo", type: "cat", energy: "low", ... }         │
│ ]                                                                   │
└─────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
3. POST /api/v1/matches/swipe
┌─────────────────────────────────────────────────────────────────────┐
│ Juan ve a Max (ID: 1) y da Like                                    │
│ {                                                                   │
│   "pet_id": 1,                                                      │
│   "is_like": true                                                   │
│ }                                                                   │
│                                                                     │
│ MatchService.Swipe(juanID=1, petID=1, isLike=true)                │
│   Match creado:                                                     │
│   - adopter_id: 1 (Juan)                                            │
│   - pet_id: 1 (Max)                                                 │
│   - status: "pending"                                               │
│   - created_at: 2025-12-22T10:30:00Z                                │
└─────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
4. Rescatista MARIA (Dueña de Max) ve solicitud
┌─────────────────────────────────────────────────────────────────────┐
│ GET /api/v1/matches/requests                                        │
│                                                                     │
│ MatchService.GetPendingRequests(mariaID)                           │
│   SELECT * FROM matches m                                          │
│   JOIN pets p ON m.pet_id = p.id                                   │
│   WHERE p.user_id = mariaID AND m.status = 'pending'               │
│                                                                     │
│ Response: [                                                         │
│   {                                                                 │
│     id: 42,                                                         │
│     adopter: { id: 1, name: "Juan", email: "juan@mail.com" },      │
│     pet: { id: 1, name: "Max", type: "dog" },                      │
│     message: "",                                                    │
│     status: "pending",                                              │
│     created_at: "2025-12-22T10:30:00Z"                              │
│   }                                                                 │
│ ]                                                                   │
└─────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
5. POST /api/v1/matches/respond
┌─────────────────────────────────────────────────────────────────────┐
│ Maria ve el perfil de Juan, aprecia que:                           │
│   - Vive en depto (adecuado para Max, perro pequeño)               │
│   - Tiene niños (Max es bueno con niños)                           │
│   - Mucho tiempo disponible (Max requiere atención)                │
│                                                                     │
│ Maria ACEPTA:                                                       │
│ {                                                                   │
│   "match_id": 42,                                                   │
│   "accept": true                                                    │
│ }                                                                   │
│                                                                     │
│ MatchService.RespondMatch(mariaID=2, matchID=42, accept=true)     │
│   Match actualizado:                                                │
│   - status: "accepted"                                              │
│   - updated_at: 2025-12-22T10:45:00Z                                │
│                                                                     │
│ [Sistema habilitaría chat entre Juan y Maria en Fase 10]          │
└─────────────────────────────────────────────────────────────────────┘
```

### Flujo Alternativo: Rechazo

```
Si Maria hubiera rechazado (accept: false):
  Match.status = "rejected"
  Juan no podría ver a Max de nuevo (excluido en GetSwipeDeck)
  Maria vería el resultado en su dashboard
```

## Algoritmo de Compatibilidad Detallado

### Hard Constraints (Obligatorios)

Estos filtros **excluyen** mascotas que no cumplen:

#### 1. Vivienda vs Patio

```go
if profile.Housing == domain.HousingApartment {
    // Si vive en depto, la mascota NO puede requerir patio
    query = query.Where("requires_yard = ?", false)
}
```

**Ejemplo**:

- Adoptante en depto → Mascota requires_yard=true → EXCLUIDA

#### 2. Niños

```go
if profile.HasChildren {
    // Si tiene niños, la mascota DEBE ser buena con niños
    query = query.Where("good_with_kids = ?", true)
}
```

**Ejemplo**:

- Adoptante con niños → Mascota good_with_kids=false → EXCLUIDA

#### 3. Otras Mascotas

```go
if profile.HasOtherPets {
    // Si tiene otras mascotas, debe ser sociable
    query = query.Where("good_with_dogs = ?", true)
}
```

**Ejemplo**:

- Adoptante con perro → Mascota good_with_dogs=false → EXCLUIDA

### Soft Constraints (Futuro)

Para Fase 10+, se pueden agregar scoring systems:

- Energía compatible (user.time_available vs pet.energy_level)
- Experiencia del adoptante vs complejidad de mascota
- Preferencia de edad/tamaño

### Eliminación de Duplicados

El algoritmo excluye mascotas con las que el usuario ya interactuó:

```go
query = query.Where("id NOT IN (?)",
    s.db.Model(&domain.Match{}).
        Select("pet_id").
        Where("adopter_id = ?", userID),
)
```

**Propósito**: Evitar que un adoptante vea la misma mascota dos veces.

## Cambios en la Base de Datos

### Nuevas Tablas

#### user_profiles

```sql
CREATE TABLE user_profiles (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT UNIQUE NOT NULL,
    housing VARCHAR(20),
    has_yard BOOLEAN,
    has_children BOOLEAN,
    has_other_pets BOOLEAN,
    experience VARCHAR(20),
    time_available VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

#### matches

```sql
CREATE TABLE matches (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    adopter_id BIGINT NOT NULL,
    pet_id BIGINT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    INDEX idx_adopter_id (adopter_id),
    INDEX idx_pet_id (pet_id),
    FOREIGN KEY (adopter_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (pet_id) REFERENCES pets(id) ON DELETE CASCADE
);
```

### Extensión a Tabla Existente: pets

```sql
ALTER TABLE pets ADD COLUMN requires_yard BOOLEAN DEFAULT false;
ALTER TABLE pets ADD COLUMN good_with_kids BOOLEAN DEFAULT false;
ALTER TABLE pets ADD COLUMN good_with_dogs BOOLEAN DEFAULT false;
ALTER TABLE pets ADD COLUMN good_with_cats BOOLEAN DEFAULT false;
ALTER TABLE pets ADD COLUMN energy_level VARCHAR(20) DEFAULT 'medium';
```

## Flujos de API

### Endpoints Principales

#### 1. Actualizar Perfil (PUT /api/v1/profile)

**Propósito**: Adoptante completa su perfil demográfico

```bash
curl -X PUT http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "housing": "apartment",
    "has_yard": false,
    "has_children": true,
    "has_other_pets": false,
    "experience": "beginner",
    "time_available": "high"
  }'
```

**Respuesta** (200 OK):

```json
{ "message": "Perfil actualizado correctamente" }
```

#### 2. Obtener Candidatos (GET /api/v1/matches/candidates)

**Propósito**: Adoptante obtiene lista de mascotas compatibles

```bash
curl -X GET http://localhost:8080/api/v1/matches/candidates \
  -H "Authorization: Bearer $TOKEN"
```

**Respuesta** (200 OK):

```json
[
  {
    "id": 1,
    "name": "Max",
    "type": "dog",
    "breed": "Golden Retriever",
    "age": 24,
    "gender": "male",
    "status": "available",
    "description": "Perro amigable y energético",
    "requires_yard": false,
    "good_with_kids": true,
    "good_with_dogs": true,
    "good_with_cats": false,
    "energy_level": "high"
  },
  ...
]
```

#### 3. Dar Like (POST /api/v1/matches/swipe)

**Propósito**: Adoptante da Like a mascota

```bash
curl -X POST http://localhost:8080/api/v1/matches/swipe \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pet_id": 1,
    "is_like": true
  }'
```

**Respuesta** (200 OK):

```json
{ "message": "Acción registrada" }
```

#### 4. Ver Solicitudes Pendientes (GET /api/v1/matches/requests)

**Propósito**: Rescatista ve Likes a sus mascotas

```bash
curl -X GET http://localhost:8080/api/v1/matches/requests \
  -H "Authorization: Bearer $TOKEN"
```

**Respuesta** (200 OK):

```json
[
  {
    "id": 42,
    "adopter": {
      "id": 1,
      "name": "Juan Pérez",
      "email": "juan@mail.com"
    },
    "pet": {
      "id": 1,
      "name": "Max",
      "type": "dog",
      "breed": "Golden Retriever"
    },
    "message": "",
    "status": "pending",
    "created_at": "2025-12-22T10:30:00Z"
  }
]
```

#### 5. Responder a Solicitud (POST /api/v1/matches/respond)

**Propósito**: Rescatista acepta o rechaza Like

```bash
curl -X POST http://localhost:8080/api/v1/matches/respond \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "match_id": 42,
    "accept": true
  }'
```

**Respuesta** (200 OK):

```json
{ "message": "Respuesta registrada" }
```

## Decisiones Arquitectónicas

### 1. Perfil Separado (UserProfile vs User)

**Razón**: Un usuario puede ser rescatista sin necesidad de llenar el perfil de adoptante.

```go
User (Siempre)        → email, password, run, role
UserProfile (Si es adoptante) → housing, has_yard, etc.
```

### 2. Hard Constraints vs Soft Constraints

**Estado actual (Etapa 2)**: Solo **hard constraints** están implementados (restricciones obligatorias). Los soft constraints (scoring, preferencias, ML) están diseñados para futuro.

**Implementación actual**:

- ✓ Hard constraints: vivienda (apartamento + patio), niños (HasChildren → GoodWithKids), mascotas (HasOtherPets → GoodWithDogs)
- ⏳ Soft constraints: scoring de compatibilidad, weighting de preferencias, machine learning

**Razón del diseño**: Evitar over-engineering. Primero validamos que el modelo básico de hard constraints funciona y proporciona valor. La arquitectura está diseñada para agregar soft constraints sin breaking changes.

### 3. GetSwipeDeck vs GetMatches

El método `GetSwipeDeck` retorna candidatos **filtrados según perfil**, no todos los matches.

**Diferencia**:

- `GetSwipeDeck`: Candidatos inteligentes (Fase 9)
- `GetMatches` (viejo): Todos los animales (Fases 1-3)

### 4. Estado Pending como Punto de Interacción

El estado `pending` actúa como punto de sincronización entre adoptantes y rescatistas:

```
Adoptante →  Swipe(Like)  → Match.status = pending
Rescatista ←  GetPending()  ← Ve qué likes tiene
Rescatista → Respond(Accept) → Match.status = accepted
```

## Escalamiento Futuro (Roadmap)

### Scoring

Agregar puntuación de compatibilidad:

```go
type MatchScore struct {
    Overall     float64 // 0-100
    HousingScore float64
    KidsScore    float64
    EnergyScore  float64
}

// GetSwipeDeck retornaría scores para UI
```

### Recomendaciones

Machine Learning para sugerir mascotas sin que el adoptante busque:

```go
func (s *MatchService) GetRecommendations(userID uint) ([]domain.Pet, error) {
    // Basado en historial, experiencia, preferences
}
```

### Filtros Dinámicos

Permitir que adoptantes filtren por edad, tamaño, energía:

```go
GetSwipeDeck(userID, filters: {age: 2-5, size: "medium", energy: "high"})
```

### Integración con Chat

Una vez que `match.status = accepted`, habilitar chat entre adoptante y rescatista.

## Cambios en CI/CD y Testing

### Testing de Matchmaking

En futuras iteraciones, se pueden agregar tests:

```go
func TestGetSwipeDeckWithChildren(t *testing.T) {
    // Adoptante con niños DEBE excluir mascotas no amigables
}

func TestSwipeDuplicateExclusion(t *testing.T) {
    // Usuario no debe ver mascota que ya visitó
}

func TestRespondenSecurity(t *testing.T) {
    // Rescatista A no puede responder matches de Rescatista B
}
```

---

## COMPLETADO EN ETAPA 5: Perfil Humanizado con Foto, Biografía y Teléfono

### Enhancements Implementados

La Etapa 5 enriqueció significativamente el modelo User de Fase 9, agregando campos que humaniza perfiles y aumenta confianza entre adoptantes y rescatistas:

#### 1. Campos Nuevos en User Model

**Extensión de** internal/core/domain/user.go:

```go
type User struct {
	ID            uint
	Email         string
	Run           string
	Password      string
	Name          string
	Role          string      // "adopter" o "rescuer"
	IsVerified    bool
	IsBanned      bool
	CreatedAt     time.Time
	UpdatedAt     time.Time

	// NUEVOS EN ETAPA 5 - Perfil Humanizado
	PhotoURL      string      // URL a foto en MinIO (ej: https://minio.paws.com/profiles/user-123.jpg)
	Bio           string      // Biografía de usuario (hasta 200 caracteres)
	Phone         string      // Teléfono o WhatsApp para contacto directo
}
```

**Tipología de campos**:

- **PhotoURL** (string): URL completa a imagen en MinIO

  - Almacenamiento: MinIO (servicio S3-compatible)
  - Validación: URL debe ser HTTPS en producción
  - Fallback: Avatar genérico si PhotoURL vacío

- **Bio** (string): Texto libre, máximo 200-500 caracteres

  - Ejemplo: "Soy abogada, amo los perros energéticos, vivo en Santiago"
  - Visible en perfil del adoptante
  - Visible en solicitud de match para rescatista

- **Phone** (string): Número de teléfono o usuario WhatsApp
  - Formato flexible (almacenado como string)
  - Puede incluir código país (+56...)
  - Visible solo en match aceptado (después de conversación inicial en chat)

#### 2. UserService.UpdateIdentity: Método de Actualización

**Nueva implementación en** internal/core/services/user_service.go:

```go
// UpdateIdentity permite actualizar campos humanizadores del perfil
// Solo campos proporcionados serán actualizados (PATCH semántica)
func (s *UserService) UpdateIdentity(
	userID uint,
	name string,
	bio string,
	phone string,
	photoURL string,
) error {
	// Construcción dinámica del mapa de actualizaciones
	updates := map[string]interface{}{
		"name":      name,
		"bio":       bio,
		"phone":     phone,
		"photo_url": photoURL,
	}

	// Actualización selectiva: solo actualiza campos en el mapa
	return s.db.Model(&domain.User{}).
		Where("id = ?", userID).
		Updates(updates).
		Error
}

// GetUser recupera usuario completo por ID
func (s *UserService) GetUser(userID uint) (*domain.User, error) {
	var user domain.User

	if err := s.db.First(&user, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, fmt.Errorf("usuario no encontrado")
		}
		return nil, err
	}

	return &user, nil
}
```

**Características del método**:

1. **Updateabilidad selectiva**: Solo campos en el map se actualizan

   - Ejemplo: UpdateIdentity(123, "Carlos", "", "", "") → solo actualiza Name
   - Otros campos permanecen sin cambios

2. **Safety**: Validación en handler, no en service

   - Service asume datos válidos
   - Handler valida formato de URL, longitud de bio, etc.

3. **Semántica PATCH**: No requiere que TODOS los campos estén presentes
   - GET /profile carga estado actual
   - Usuario modifica algunos campos
   - PUT /profile actualiza solo los modificados

#### 3. Handlers HTTP: PUT /profile y GET /profile

**Nuevos handlers en** internal/transport/http/user_handler.go:

```go
type UpdateProfileRequest struct {
	Name     string `json:"name" binding:"required"`
	Bio      string `json:"bio"`
	Phone    string `json:"phone"`
	PhotoURL string `json:"photo_url"`
}

func (h *UserHandler) UpdateProfile(c *gin.Context) {
	// Extraer userID del JWT
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validaciones
	if req.Name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "nombre requerido"})
		return
	}
	if len(req.Bio) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "biografía demasiado larga"})
		return
	}

	// Actualizar
	if err := h.userService.UpdateIdentity(
		userID,
		req.Name,
		req.Bio,
		req.Phone,
		req.PhotoURL,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "error actualizando perfil"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "perfil actualizado"})
}

func (h *UserHandler) GetProfile(c *gin.Context) {
	// Extraer userID del JWT
	userID, err := h.getUserIDFromContext(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Obtener usuario completo
	user, err := h.userService.GetUser(userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "usuario no encontrado"})
		return
	}

	c.JSON(http.StatusOK, user)
}
```

**Endpointsregistrados en** cmd/api/main.go:

```go
// Protegidas (requieren JWT)
protected.PUT("/profile", userHandler.UpdateProfile)
protected.GET("/profile", userHandler.GetProfile)
```

**Semántica REST**:

- **GET /profile**: Obtiene perfil actual del usuario (pre-llena formulario)
- **PUT /profile**: Actualiza perfil completo (name, bio, phone, photo_url)

#### 4. Flujo Completo: Edición de Perfil

**Caso de uso: Adoptante completa su perfil**

```
1. Adopter abre MainLayout → Tab "Perfil" (EditProfileScreen)
2. Pantalla ejecuta GET /profile
   - Respuesta: {name: "Juan", bio: "", phone: "", photo_url: ""}
   - Campos se cargan en TextFormField

3. Usuario:
   - Toma foto (image_picker)
   - Completa nombre: "Juan Carlos"
   - Escribe bio: "Programador, vivo en Ñuñoa, amo los perros medianos"
   - Ingresa teléfono: "+56912345678"

4. Presiona "Guardar"
   - Foto se sube a MinIO (FileService.uploadFile)
   - Retorna URL: "https://minio.paws.com/profiles/user-123-1701234567.jpg"
   - Ejecuta PUT /profile con:
     {
       "name": "Juan Carlos",
       "bio": "Programador, vivo en Ñuñoa, amo los perros medianos",
       "phone": "+56912345678",
       "photo_url": "https://minio.paws.com/profiles/user-123-1701234567.jpg"
     }

5. Backend ejecuta UpdateIdentity(123, name, bio, phone, photoURL)
   - Actualiza usuario en BD
   - Respuesta 200 OK

6. Frontend navega atrás
   - Próximo swipe mostrará foto en match
   - Rescatista ve bio cuando recibe solicitud
```

#### 5. Integración con MatchScreen y Solicitudes

**Cómo afecta a visualización de matches**:

En MatchScreen cuando se presenta una mascota:

```dart
// ANTES (Etapa 2): Solo mascota
Card(
  child: Column(
    children: [
      Image.network(pet.imageUrl),
      Text(pet.name),
      Text(pet.breed),
    ],
  ),
),

// DESPUÉS (Etapa 5): Incluye rescatista
Card(
  child: Column(
    children: [
      Stack(
        children: [
          Image.network(pet.imageUrl),
          // Avatar del rescatista (foto + nombre)
          Positioned(
            top: 10,
            right: 10,
            child: CircleAvatar(
              backgroundImage: NetworkImage(pet.user.photoUrl),
              child: Text(pet.user.name),
            ),
          ),
        ],
      ),
      Text(pet.name),
      Text(pet.breed),
    ],
  ),
),
```

En MatchRequestsScreen (para rescatista) cuando ve solicitud de adopción:

```dart
// Tarjeta de solicitud entrante
Card(
  child: ListTile(
    leading: CircleAvatar(
      backgroundImage: NetworkImage(match.adopter.photoUrl),
    ),
    title: Text(match.adopter.name),
    subtitle: Text(match.adopter.bio),
    trailing: IconButton(
      icon: Icon(Icons.phone),
      onPressed: () => _launchWhatsApp(match.adopter.phone),
    ),
  ),
),
```

**Ventaja**: Rescatista ve nombre, foto y bio de adoptante ANTES de aceptar

- Evaluación rápida de compatibilidad
- Reduce aceptación de perfiles sospechosos
- Aumenta confianza mutua

#### 6. Impacto en Confianza

**Antes (Etapa 4 Fase 9)**:

- Adopter ve mascota pero no rescatista
- Rescatista ve "Usuario #123" sin foto/nombre
- Match aceptado → primer contacto en chat "¿Quién eres?"
- Friction alta

**Después (Etapa 5)**:

- Adopter ve mascota + rescatista (foto + nombre)
- Rescatista ve "Juan Carlos" (foto + bio + teléfono)
- Match aceptado → ambos conocen quién es el otro
- Puente directo vía WhatsApp si contacto directo
- Friction baja, confianza alta

**Métricas esperadas**:

- ✓ Aceptación de matches: +80% (humanización)
- ✓ Cancelación post-match: -50% (mejor evaluación)
- ✓ Adopciones completadas: +60% (menos fricción)

#### 7. Casos de Uso Mejorados

**Caso 1: Adopter Busca en MainLayout**

1. Click "Descubrir" → MatchScreen con swipe
2. Ve mascota "Duque" (foto, raza)
3. Ve rescatista "Fundación PawsRescue" (logo, nombre)
4. Click "Like" → Match pendiente

**Caso 2: Rescatista Revisa Solicitudes**

1. Click "Solicitudes" → MatchRequestsScreen
2. Ve solicitud de "Juan Carlos" (foto, bio, teléfono)
3. Verifica que bio indica experiencia ("programador" → probablemente responsable)
4. Click "Aceptar" → chat abierto
5. Puede llamar directo al +56912345678 si necesita urgente

**Caso 3: Adopter Completa Perfil**

1. Login exitoso → MainLayout
2. Click "Perfil" → EditProfileScreen
3. Carga GET /profile (vacío si primera vez)
4. Selecciona foto de galería
5. Completa "Juan Carlos", "Soy abogada, amo los gatos"
6. Presiona Guardar
7. Próximo swipe: foto visible en profile card

#### 8. Integración con Prior Etapas

**Relación con Etapa 2 (Matchmaking)**:

- Fase 9 Etapa 2: Algoritmo GetSwipeDeck retorna mascotas compatibles
- Etapa 5: GetSwipeDeck ahora retorna mascota + rescatista con foto/bio/teléfono
- Sin cambios en backend, solo visualización mejorada en frontend

**Relación con Etapa 3 (Geolocalización)**:

- Etapa 3: SearchNearby retorna mascotas por distancia
- Etapa 5: Photo/Bio del rescatista visible en búsqueda geografizada
- Adopter ahora elige: "¿Qué mascota?" Y "¿Confío en este rescatista?"

**Relación con Etapa 4 (Chat)**:

- Etapa 4: Chat texto entre adopter y rescatista
- Etapa 5: Chat enriquecido con nombres/fotos visibles
- Teléfono disponible para contacto directo WhatsApp

#### 9. Consideraciones de Privacidad

**Datos públicos vs privados**:

| Campo    | Antes Match | Después Match | Notas                             |
| -------- | ----------- | ------------- | --------------------------------- |
| Name     | Visible     | Visible       | Identifier de usuario             |
| PhotoURL | Visible     | Visible       | Genera confianza                  |
| Bio      | Visible     | Visible       | Información compartida voluntaria |
| Phone    | Oculto      | Visible       | Solo después de match aceptado    |
| Email    | Oculto      | Oculto        | Nunca compartida vía API          |

**Implementación en frontend**:

```dart
// MatchRequestsScreen: NO mostrar phone hasta que match sea aceptado
if (match.status == 'accepted') {
  Text('Teléfono: ${adopter.phone}');  // Visible
} else {
  Text('Teléfono: disponible si aceptas');  // Oculto
}
```

#### 10. Roadmap: Humanización Progresiva

**Futuras mejoras en Etapa 6+**:

1. **Badges de verificación**:

   - ✓ Email verificado
   - ✓ Teléfono verificado
   - ✓ ID nacional verificado (Fase 8)
   - Aumenta confianza visual

2. **Reviews/Ratings**:

   - Rescatista: 4.8/5 (12 adopciones)
   - Adopter: 4.5/5 (3 mascotas)
   - Señala historial exitoso

3. **Campos adicionales de perfil**:

   - Experiencia ("Primer perro", "Experto")
   - Ubicación general ("Santiago Centro", "Puente Alto")
   - Mascotas actuales ("2 gatos", "1 perro")

4. **Recomendaciones de compatibilidad**:
   - "Juan ama perros energéticos, Duque es Husky"
   - "Tu perfil es perfecto para familias con niños"

## COMPLETADO EN ETAPA 9: Contenedorización y Estabilidad de Infraestructura

### Integración con Docker Compose

Etapa 9 asegura que el algoritmo de matchmaking de Fase 9 funcione de manera confiable tanto en desarrollo local como en la nube (Railway). La contenedorización total de servicios garantiza que postgres.go, MatchService, GetSwipeDeck() y todos los dependientes de base de datos ejecuten en un entorno predecible.

**Implicaciones para Fase 9**:

```go
// services/match_service.go - GetSwipeDeck() depende de conexión estable
func (s *MatchService) GetSwipeDeck(userID uint) ([]Pet, error) {
    // Etapa 9 asegura que s.db es una conexión GORM válida
    // Ya sea local (PostgreSQL Docker) o nube (Supabase)

    profile := s.getProfile(userID)
    query := s.db.Where("status = ?", PetAvailable)
    // ... filtros AND (housing, kids, other_pets) ...
    var candidates []Pet
    query.Find(&candidates)
    return candidates, nil
}
```

### Base de Datos Híbrida y Migraciones

El modelo UserProfile y la extensión Pet (requeridos por Fase 9) se migran automáticamente en ambos entornos:

**Local (docker-compose)**:

```bash
docker-compose up

# PostgreSQL inicia en puerto 5432
# main.go ejecuta AutoMigrate()
# ✓ Tabla user_profiles creada localmente
# ✓ Campos de pet compatibility creados
# GetSwipeDeck() funciona inmediatamente
```

**Cloud (Railway + Supabase)**:

```
// .env en Railway dashboard
DATABASE_URL=postgresql://...@supabase.com:6543/postgres

// main.go detecta DATABASE_URL y conecta a Supabase
// AutoMigrate() ejecuta contra Supabase
// ✓ Tabla user_profiles creada en Supabase
// ✓ GetSwipeDeck() funciona con datos reales
```

### GetSwipeDeck() en Etapa 9 - Optimización SQL

Etapa 4 mejoró GetSwipeDeck() con SQL puro LEFT JOIN para eliminar duplicados. Etapa 9 asegura que esta optimización funciona tanto localmente como en Supabase:

```go
// services/match_service.go
func (s *MatchService) GetSwipeDeck(userID uint) ([]Pet, error) {
    var profile UserProfile
    if err := s.db.Where("user_id = ?", userID).First(&profile).Error; err != nil {
        // Fallback: usuario sin perfil - mostrar todas mascotas
        profile = getDefaultProfile()
    }

    query := s.db.Where("pets.status = ?", "available").
        Joins("LEFT JOIN matches ON pets.id = matches.pet_id AND matches.adopter_id = ?", userID).
        Where("matches.id IS NULL")  // Excluir ya vistas

    // Aplicar hard constraints basados en perfil
    if profile.Housing == "apartment" {
        query = query.Where("pets.requires_yard = ?", false)
    }
    if profile.HasChildren {
        query = query.Where("pets.good_with_kids = ?", true)
    }
    if profile.HasOtherPets {
        query = query.Where("pets.good_with_dogs = ? OR pets.good_with_cats = ?", true, true)
    }

    var candidates []Pet
    if err := query.Find(&candidates).Error; err != nil {
        log.Printf("Error en GetSwipeDeck: %v", err)
        return []Pet{}, err
    }

    return candidates, nil
}
```

**Garantías en Etapa 9**:

- **PostgreSQL Local**: LEFT JOIN funciona exactamente igual
- **Supabase (PostgreSQL 15)**: LEFT JOIN soportado nativamente
- **Performance**: Índices automáticos en ambas BD para pet.status y matches.pet_id
- **Escalabilidad**: Misma query ejecuta con 100 o 10,000 mascotas

### Tolerancia a Fallos en Matchmaking

MinIO/almacenamiento en Etapa 9 no bloquea MatchService. Si fotograf de mascotas no están disponibles:

```go
// transport/http/match_handler.go
func (h *MatchHandler) GetSwipeDeck(c *gin.Context) {
    candidates, err := h.service.GetSwipeDeck(userID)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Error en matchmaking"})
        return
    }

    // Intentar cargar photos, pero continuar si fallan
    for i, pet := range candidates {
        if pet.PhotoURL != "" {
            // Photo existe (MinIO disponible)
            candidates[i].PhotoURL = h.getSignedURL(pet.PhotoURL)
        } else {
            // Photo no disponible - usar placeholder
            candidates[i].PhotoURL = "https://cdn.example.com/placeholder.png"
        }
    }

    c.JSON(http.StatusOK, gin.H{"candidates": candidates})
}
```

**Resultado**: Usuarios ven mascotas sin fotos si MinIO no está disponible. No afecta funcionalidad core de matchmaking.

### Testing Local de Fase 9 en Etapa 9

**Setup**:

```bash
# Terminal 1
docker-compose up

# Terminal 2 - Ver logs
docker-compose logs -f backend

# Terminal 3 - Tester
```

**Scenario 1: Crear Adoptante con Perfil**:

```bash
# 1. Registrar usuario (adopter)
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Juan Pérez",
    "email": "juan@test.com",
    "password": "test123",
    "run": "12345678-1",
    "role": "adopter"
  }'
# Respuesta: 201 Created, token en respuesta

# 2. Actualizar perfil demográfico
curl -X PUT http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer [TOKEN]" \
  -H "Content-Type: application/json" \
  -d '{
    "housing": "apartment",
    "has_yard": false,
    "has_children": true,
    "has_other_pets": false,
    "experience": "beginner",
    "time_available": "high"
  }'
# Respuesta: 200 OK
```

**Scenario 2: GetSwipeDeck Aplicando Hard Constraints**:

```bash
# Obtener mascotas compatibles (sin requerimiento de patio, safe con niños)
curl -X GET http://localhost:8080/api/v1/matches/candidates \
  -H "Authorization: Bearer [TOKEN]"

# Respuesta (solo mascotas que cumplen: requires_yard=false Y good_with_kids=true)
{
  "candidates": [
    {
      "id": 1,
      "name": "Bella",
      "type": "dog",
      "breed": "Poodle",
      "age": 3,
      "requires_yard": false,
      "good_with_kids": true,
      "good_with_dogs": true,
      "energy_level": "medium"
    },
    {
      "id": 2,
      "name": "Misu",
      "type": "cat",
      "breed": "Siamese",
      "age": 2,
      "requires_yard": false,
      "good_with_kids": true,
      "good_with_dogs": false,
      "energy_level": "low"
    }
  ]
}
```

**Scenario 3: Swipe y Respuesta del Rescatista**:

```bash
# Adoptante swipeadera
curl -X POST http://localhost:8080/api/v1/matches/swipe \
  -H "Authorization: Bearer [ADOPTER_TOKEN]" \
  -H "Content-Type: application/json" \
  -d '{"pet_id": 1, "is_like": true}'
# Crea Match(adopter=Juan, pet=Bella, status=PENDING)

# Rescatista ve solicitud
curl -X GET http://localhost:8080/api/v1/matches/requests \
  -H "Authorization: Bearer [RESCUER_TOKEN]"

# Rescatista responde
curl -X POST http://localhost:8080/api/v1/matches/respond \
  -H "Authorization: Bearer [RESCUER_TOKEN]" \
  -H "Content-Type: application/json" \
  -d '{"match_id": 1, "accept": true}'
# Match.status = ACCEPTED → Chat habilitado
```

### Ventajas de Fase 9 en Etapa 9

1. **Infraestructura Sólida**: Matchmaking funciona en laptop y cloud idénticamente
2. **Escalabilidad**: LEFT JOIN SQL no depende de aplicación, escalable a millones de mascotas
3. **Resiliencia**: Fallos en almacenamiento no rompen matching
4. **Testabilidad**: Docker Compose proporciona entorno reproducible
5. **Rendimiento**: Hard constraints filtran en BD, no en aplicación

## COMPLETADO EN ETAPA 15: Visibilidad de Perfil Adoptante en Solicitudes Pendientes

### Problema Resuelto: Información Incompleta en Solicitudes

Rescatista María recibe "like" de Juan a su mascota. El endpoint GET /matches/requests retornaba solo datos básicos del adoptante (ID, nombre, email). María no sabía:

- ¿Vive en casa o departamento?
- ¿Tiene patio?
- ¿Qué experiencia tiene con mascotas?
- ¿Tiene otras mascotas?
- ¿Cuánto tiempo puede dedicar?

Resultado: Aceptaba solicitudes que fallaban después.

### Solución Implementada

Se extendió el modelo User (lado backend) con 8 campos nuevos:

```go
// internal/core/domain/user.go

type User struct {
    // ... campos existentes ...

    // NUEVOS CAMPOS ETAPA 15
    HousingType       string `gorm:"type:varchar(50);default:'House'" json:"housing_type"`
    HousingOwnership  string `gorm:"type:varchar(50);default:'Owned'" json:"housing_ownership"`
    HasYard           bool   `gorm:"default:false" json:"has_yard"`
    HasFence          bool   `gorm:"default:false" json:"has_fence"`
    FamilyComposition string `gorm:"type:varchar(100);default:'Single'" json:"family_composition"`
    OtherPets         string `gorm:"type:varchar(100);default:'None'" json:"other_pets"`
    TimeAvailability  string `gorm:"type:varchar(50);default:'Medium'" json:"time_availability"`
    Experience        string `gorm:"type:varchar(50);default:'Beginner'" json:"experience"`
}
```

Estos campos se incluyen automáticamente en respuestas JSON cuando se consulta usuario completo.

### Cambios en MatchService

El método `GetPendingRequests()` ahora precarga información completa del adoptante:

```go
// internal/core/services/match_service.go

func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
    var matches []domain.Match
    err := s.db.Table("matches").
        Joins("JOIN pets ON matches.pet_id = pets.id").
        Preload("Adopter").  // ← PRECARGA INFORMACIÓN COMPLETA DEL ADOPTANTE (todos 8 campos nuevos)
        Preload("Pet").
        Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
        Find(&matches).Error
    return matches, err
}
```

### Respuesta JSON Mejorada

Antes de Etapa 15:

```json
{
  "id": 42,
  "adopter": {
    "id": 1,
    "name": "Juan",
    "email": "juan@mail.com"
  },
  "pet": { ... },
  "status": "pending"
}
```

Después de Etapa 15:

```json
{
  "id": 42,
  "adopter": {
    "id": 1,
    "name": "Juan",
    "email": "juan@mail.com",
    "bio": "Amo los perros activos",
    "phone": "+56912345678",
    "photo_url": "https://minio/usuarios/juan.jpg",
    "housing_type": "Apartment",
    "housing_ownership": "Rented",
    "has_yard": false,
    "has_fence": false,
    "family_composition": "Couple",
    "other_pets": "Cats",
    "time_availability": "High",
    "experience": "Intermediate"
  },
  "pet": { ... },
  "status": "pending",
  "created_at": "2025-01-15T10:30:00Z"
}
```

### Visualización en Frontend (MatchRequestsScreen)

Rescatista ahora ve tarjeta detallada en "Solicitudes Pendientes":

```dart
// Renderizado mejorado de solicitud
Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header con foto y nombre
        Row(
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(adopter.photoUrl ?? ''),
              radius: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adopter.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    adopter.bio ?? 'Sin bio',
                    style: const TextStyle(color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Información de hogar
        Text(
          'Vivienda',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            Chip(label: Text(adopter.housingType)), // "Apartment"
            Chip(label: Text(adopter.housingOwnership)), // "Rented"
            if (adopter.hasYard) const Chip(label: Text('Tiene Patio')),
            if (adopter.hasFence) const Chip(label: Text('Tiene Cerca')),
          ],
        ),
        const SizedBox(height: 12),

        // Información de familia
        Text(
          'Familia',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text('Composición: ${adopter.familyComposition}'),
        Text('Otras mascotas: ${adopter.otherPets}'),
        const SizedBox(height: 12),

        // Información de experiencia
        Text(
          'Experiencia',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text('Disponibilidad: ${adopter.timeAvailability}'),
        Text('Experiencia: ${adopter.experience}'),
        const SizedBox(height: 16),

        // Mascota de interés
        Text(
          'Interesado en: ${pet.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 12),

        // Botones de decisión
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () => _respondMatch(matchId, true),
              icon: const Icon(Icons.check),
              label: const Text('Aceptar'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
            ElevatedButton.icon(
              onPressed: () => _respondMatch(matchId, false),
              icon: const Icon(Icons.close),
              label: const Text('Rechazar'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
      ],
    ),
  ),
)
```

### Impacto en Decisiones de Matching

Rescatista ahora puede verificar compatibilidad ANTES de aceptar:

**Ejemplo 1: Mascota requiere patio + Adopter sin patio**

- Rescatista ve: "Apartment, No patio" → Rechaza inmediatamente
- Resultado: Adopción fallida evitada

**Ejemplo 2: Mascota buena con gatos + Adopter tiene gatos**

- Rescatista ve: "Other pets: Cats" + "good_with_cats: true" → Acepta con confianza
- Resultado: Probabilidad de éxito aumentada

**Ejemplo 3: Mascota energética requiere experiencia + Adopter principiante**

- Rescatista ve: "Experience: Beginner" + "Energy level: high" → Ofrece sesión de asesoramiento antes de aceptar
- Resultado: Adopción educada, no rechazada

### Beneficios de Etapa 15 en Matching

**Para Rescatistas**:

- Información COMPLETA antes de decidir (no después)
- Menos rechazos tardíos por incompatibilidad
- Confianza aumentada en decisiones
- Reducción de estrés por toma de decisiones

**Para Adoptantes**:

- Sistema más justo: decisiones basadas en información real
- Menos rechazos inesperados ("¿por qué rechazó mi solicitud?")
- Siente que rescatista lo conoce/consideró realmente

**Para el Sistema**:

- Tasa de adopción exitosa aumenta
- Devoluciones post-adopción disminuyen
- Datos más ricos para potencial matching inteligente futuro
- Escalabilidad: campos extensibles sin cambio de schema

### Notas Arquitectónicas - Etapa 15 (Backend)

- **Backward Compatibility**: Todos los campos tienen defaults. Usuarios sin esta información ven valores por defecto sensatos.
- **Eager Loading**: Preload("Adopter") garantiza que información se carga en una consulta, no N+1 queries.
- **JSON Mapping**: Tags gorm y json alinean nombres de Go (HousingType) con JSON (housing_type) automáticamente.
- **Migraciones Automáticas**: GORM detecta campos nuevos y crea columnas con defaults sin ruptura.
- **Escalabilidad**: Si en futuro se quieren agregar más campos (ocupación, presupuesto, etc.), estructura soporta sin cambios.

## Referencias

- PhotoURL storage: MinIO S3 API v4
- Bio validation: GORM text type, MAX_LENGTH constraint
- Privacy considerations: GDPR, personal data handling

## NOTA FINAL: Relación entre Fase 9 (Especulativa) y Etapa 2 (Implementación Real)

Esta documentación de Fase 9 fue concebida como un diseño prospectivo de lo que sería una arquitectura de matchmaking "ideal". Simultáneamente, se desarrolló Etapa 2 que implementa **precisamente los componentes fundamentales descritos en esta Fase 9**, pero con un enfoque pragmático y sin sobrecarga innecesaria.

### Alineamiento:

| Componente                          | Fase 9 (Diseño)          | Etapa 2 (Implementación)       | Estado |
| ----------------------------------- | ------------------------ | ------------------------------ | ------ |
| UserProfile                         | ✓ Descrito               | ✓ Implementado                 | PROD   |
| Pet compatibility fields            | ✓ Descrito               | ✓ Implementado (5 campos)      | PROD   |
| GetSwipeDeck con hard constraints   | ✓ Descrito               | ✓ Implementado (3 filtros AND) | PROD   |
| Swipe (Like/Dislike)                | ✓ Descrito               | ✓ Implementado                 | PROD   |
| Rescatista response (Accept/Reject) | ✓ Descrito               | ✓ Implementado                 | PROD   |
| Tabla Match                         | ✓ Descrito               | ✓ Implementado                 | PROD   |
| Scoring/ML                          | ✓ Mencionado como futuro | ⏳ No implementado             | FUTURE |
| Soft constraints                    | ✓ Mencionado como futuro | ⏳ No implementado             | FUTURE |
| Chat integration                    | ✓ Mencionado como futuro | ⏳ No implementado             | FUTURE |

### Ventajas de Etapa 2 vs "Fase 9 Completa":

1. **Pragmatismo**: No bloquea features avanzadas. Deliver valor inmediato.
2. **Claridad**: Hard constraints son predecibles, fáciles de testear y debuggear.
3. **Performance**: Filtrado en SQL, no N+1 queries, escalable.
4. **Extensibilidad**: Arquitectura permite agregar soft constraints sin breaking changes.
5. **Mantenibilidad**: Código limpio, servicios bien separados, bajo acoplamiento.

### Para Agregar Soft Constraints (Futuro):

1. MatchService.GetSwipeDeck() puede retornar `[]PetWithScore` en lugar de `[]Pet`
2. Agregar método MatchService.ScorePet(userProfile, pet) → float64
3. Sort results por score en cliente
4. Metrics/analytics para feedback ML

La arquitectura de Etapa 2 soporta todo esto sin cambios al database schema.

### Conclusión:

Fase 9 en esta documentación es el "state of the art" completo del matchmaking inteligente. Etapa 2 es el "MVP del matchmaking" que ya está en producción. Las secciones de Fase 9 sobre Scoring, ML, y Soft Constraints permanecen como **roadmap documentado para la próxima iteración**.
