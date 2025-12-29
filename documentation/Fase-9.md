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
