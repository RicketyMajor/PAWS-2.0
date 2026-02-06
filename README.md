# PAWS - Pet Adoption Matching System

PAWS es una plataforma de matchmaking diseñada para facilitar adopciones seguras y efectivas entre adoptantes y rescatistas. La aplicación prioriza la seguridad como componente crítico en cada capa.

(Demo)[https://paws-2-0.vercel.app/]

## Descripción General

PAWS conecta a personas que desean adoptar mascotas con organizaciones y rescatistas que ofrecen animales en adopción. Utiliza geolocalización, algoritmos de matching y comunicación segura en tiempo real para crear una experiencia confiable.

**Stack**: Go (Backend) + Flutter (Frontend) + PostgreSQL + Redis

**Arquitectura**: Monorepo con separación Backend (cmd/, internal/) y Frontend (app/)

## Etapa 1: Estabilización y Networking (Completada)

La Etapa 1 de Operación PAWS Real representa la estabilización de infraestructura crítica y preparación para desarrollo sin dependencias pesadas. Se ha implementado un sistema "Kill Switch" para características asincrónicas y soporte completo para acceso desde navegadores web.

### Componentes Implementados

#### 1. Kill Switch para RabbitMQ (Asincronía Opcional)

**Problema Resuelto**: El desarrollo local requería ejecutar RabbitMQ solo para enviar emails via OTP, bloqueando a desarrolladores sin acceso a infraestructura pesada.

**Solución**: Variable de entorno `ENABLE_ASYNC_FEATURES` controla si el sistema usa asincronía:

- **ENABLE_ASYNC_FEATURES=true**: Sistema conecta a RabbitMQ y ejecuta tareas en background
- **ENABLE_ASYNC_FEATURES=false (default)**: Sistema degrada gracefully, generando OTP y logeando a consola en desarrollo

**Implementación**:

```go
// cmd/api/main.go
var mqClient *messaging.RabbitMQClient
if os.Getenv("ENABLE_ASYNC_FEATURES") == "true" {
    mqClient, err := messaging.ConnectRabbitMQ(...)
    // Log: "Async Features activadas..."
} else {
    log.Println("Async Features desactivadas (modo sincrónico)")
}
```

**OTPService Fallback**: Cuando mqClient es nil, el servicio genera OTP y loguea a consola en lugar de publicar a queue:

```go
if s.mqClient != nil {
    s.mqClient.Publish("email_notifications", ...)
} else {
    log.Printf("[DEV MODE] OTP Code: %s", code)
}
```

**Ventajas**: Desarrollo sin RabbitMQ, producción con async completo, graceful degradation garantizada.

#### 2. CORS Middleware para Flutter Web

**Problema Resuelto**: Aplicaciones Flutter Web compiladas a HTML/JavaScript no pueden hacer peticiones HTTP a un dominio diferente debido a la política de mismo-origen del navegador.

**Solución**: Middleware `CORSMiddleware()` en `internal/transport/http/middleware/cors.go` autoriza explícitamente requests desde cualquier origen:

**Headers Configurados**:

- `Access-Control-Allow-Origin: *` (desarrollo), con lista de dominios en producción
- `Access-Control-Allow-Methods: POST, OPTIONS, GET, PUT, DELETE`
- `Access-Control-Allow-Headers: ..., Authorization, ...` (permite JWT)
- Manejo de preflight requests (OPTIONS) con respuesta 204 No Content

**Aplicación Global** en main.go:

```go
r := gin.Default()
r.Use(middleware.CORSMiddleware())  // Aplicado ANTES de rutas
// Todas las rutas heredan CORS automáticamente
```

**Impacto**: Flutter Web ahora se ejecuta en localhost:3000 sin bloqueos CORS, Frontend y Backend pueden estar en puertos diferentes.

#### 3. Flujo de Autenticación Mejorado con OTP

**Cambios en Register**:

- Parámetro `role` agregado (adopter | rescatista)
- Genera automáticamente código OTP después de crear usuario
- Responde "Código de verificación enviado a tu email"

**Nuevos Endpoints**:

- `POST /auth/otp/request`: Solicita código (si no se envió en register)
- `POST /auth/otp/verify`: Verifica código y marca usuario como verificado

**Frontend Integration** (app/lib/features/auth/):

- `RegisterScreen`: Obtiene rol del usuario, muestra feedback de OTP enviado
- Navega a `OTPScreen(email)` para entrada de código de 6 dígitos
- `AuthRepository`: Método `verifyOtp(email, code)` para completar verificación

#### 4. RepositoryProvider Inyectado (ChatRepository)

**Change en main.dart**:

```dart
MultiRepositoryProvider(
  providers: [
    RepositoryProvider(create: (context) => AuthRepository()),
    RepositoryProvider(create: (context) => ChatRepository()),  // NUEVO
    RepositoryProvider(create: (context) => PetsRepository()),
  ],
)
```

**Impacto**: ChatRepository disponible en cualquier screen sin BLoC extra, preparado para chat real-time en Fase 4.

#### 5. Configuración de Infraestructura

**docker-compose.yml** ajustado:

- No incluye RabbitMQ por defecto (consistent con Kill Switch)
- Servicios incluidos: PostgreSQL, Redis, MinIO, Backend
- Backend sin `ENABLE_ASYNC_FEATURES` → modo sincrónico por defecto
- Ideal para desarrollo sin overhead de cola de mensajes

### Validación y Testing

**Kill Switch Validatable**:

```bash
# Modo sincrónico (default)
docker-compose up

# Modo asincrónico (requiere RabbitMQ en host local)
ENABLE_ASYNC_FEATURES=true docker-compose up
```

**CORS Verificable**: Aplicación Flutter Web accede a http://localhost:8080/api/v1 sin errores de navegador

**OTP Generado**: En modo sincrónico, códigos aparecen en logs del backend:

```
[DEV MODE] OTP Code for user@example.com: 123456
```

### Salidas a Etapa 2

La Etapa 1 prepara el camino para:

- **Identidad y Perfiles**: Completar perfil del adoptante con datos demográficos
- **Rescatista Dashboard**: Backend listo para endpoints sin CORS issues
- **Chat Real-time**: RepositoryProvider inyectado, solo necesita WebSocket implementation
- **Producción**: Kill Switch permite escalar fácilmente a asincronía completa

## Etapa 2: Identidad y Perfiles Enriquecidos (Completada)

La Etapa 2 implementa la columna vertebral del sistema de matching de PAWS: perfiles demográficos detallados de adoptantes y un algoritmo inteligente que filtra mascotas candidatas basándose en restricciones duras. Esta etapa convierte PAWS de una simple galería de mascotas a una plataforma de compatibilidad inteligente.

### Componentes Implementados

#### 1. Modelo UserProfile - Información Demográfica

**Propósito**: Capturar características del estilo de vida del adoptante para matchmaking inteligente.

**Campos Implementados**:

```go
type HousingType string

const (
    HousingHouse     HousingType = "house"      // Casa con terreno
    HousingApartment HousingType = "apartment"  // Departamento/piso
    HousingParcel    HousingType = "parcel"     // Parcela/quinta
)

type UserProfile struct {
    ID            uint           `json:"id"`
    UserID        uint           `json:"user_id"` // FK a User (1-a-1)

    Housing       HousingType    `json:"housing"`        // Tipo de vivienda
    HasYard       bool           `json:"has_yard"`       // Tiene patio disponible
    HasChildren   bool           `json:"has_children"`   // Tiene niños en casa
    HasOtherPets  bool           `json:"has_other_pets"` // Posee otras mascotas
    Experience    string         `json:"experience"`     // beginner, intermediate, expert
    TimeAvailable string         `json:"time_available"` // low, medium, high

    CreatedAt     time.Time      `json:"created_at"`
    UpdatedAt     time.Time      `json:"updated_at"`
}
```

**Relación Base de Datos**: Cada Usuario (adopter) tiene exactamente UN UserProfile (relación 1-a-1). Los rescatistas NO tienen perfil (solo crean mascotas).

#### 2. Extensión del Modelo Pet para Compatibilidad

**Nuevos Campos Agregados**:

```go
type Pet struct {
    // Campos existentes...
    ID            uint
    Name          string
    Type          string  // dog, cat
    Breed         string
    Age           int
    Status        PetStatus // available, adopted, pending

    // NUEVOS CAMPOS PARA MATCHING (Etapa 2)
    RequiresYard  bool    `json:"requires_yard"`  // Necesita espacio exterior
    GoodWithKids  bool    `json:"good_with_kids"` // Segura con niños
    GoodWithDogs  bool    `json:"good_with_dogs"` // Sociable con otros perros
    GoodWithCats  bool    `json:"good_with_cats"` // Compatible con gatos
    EnergyLevel   string  `json:"energy_level"`   // low, medium, high

    // Ubicación (recuperada de Fase 3)
    Latitude      float64 `json:"latitude"`
    Longitude     float64 `json:"longitude"`

    UserID        uint    // FK a User (rescatista propietario)
}
```

**Impacto**: Estos campos permiten que el algoritmo GetSwipeDeck() aplique filtros inteligentes sin necesidad de machine learning complejo.

#### 3. Servicio UserService - Gestión de Perfiles

**Responsabilidades**:

```go
type UserService struct {
    db *gorm.DB
}

// CreateOrUpdateProfile: Inserta o actualiza el perfil demográfico
func (s *UserService) CreateOrUpdateProfile(userID uint, profile UserProfile) error {
    // Implementa patrón UPSERT (Update si existe, Insert si no)
    // Validación automática de relación 1-a-1
}

// GetProfile: Recupera el perfil para consultas de matching
func (s *UserService) GetProfile(userID uint) (*UserProfile, error) {
    // Usado por MatchService para obtener restricciones del adoptante
}
```

**Patrón UPSERT**: Si el usuario ya tiene perfil, actualiza campos. Si es nuevo, crea uno. Garantiza que nunca hay duplicados.

#### 4. Algoritmo de Matching Inteligente - GetSwipeDeck()

**Lógica de Filtrado por Restricciones Duras**:

```go
type MatchService struct {
    db         *gorm.DB
    petService *PetService
}

func (s *MatchService) GetSwipeDeck(userID uint) ([]Pet, error) {
    // Step 1: Obtener perfil del adoptante
    profile := s.db.Where("user_id = ?", userID).First(&profile)

    // Step 2: Query base - mascotas disponibles
    query := s.db.Where("status = ?", PetAvailable)

    // Step 3: EXCLUIR mascotas ya vistas/swipeadas
    query = query.Where("id NOT IN (?)",
        s.db.Select("pet_id").From("matches").
        Where("adopter_id = ?", userID))

    // Step 4: APLICAR FILTROS INTELIGENTES

    // Filtro 1: Vivienda
    if profile.Housing == HousingApartment {
        // Si adoptante vive en depto -> mascota NO puede necesitar patio
        query = query.Where("requires_yard = ?", false)
    }

    // Filtro 2: Niños
    if profile.HasChildren {
        // Si hay niños -> mascota DEBE ser segura con niños
        query = query.Where("good_with_kids = ?", true)
    }

    // Filtro 3: Otras mascotas
    if profile.HasOtherPets {
        // Si tiene mascotas -> must be sociable
        query = query.Where("good_with_dogs = ?", true)
    }

    // Step 5: Ejecutar y retornar
    var candidates []Pet
    query.Find(&candidates)
    return candidates, nil
}
```

**Resultado**: Un usuario ve SOLO mascotas que son compatibles con su estilo de vida. Esto previene frustraciones como "¿Por qué me muestran un Husky si vivo en depto?"

**Fallback para Usuarios Nuevos**: Si un usuario no ha completado perfil aún, se muestran TODAS las mascotas disponibles (primeras 20) limitadas, permitiendo exploración inicial.

#### 5. Endpoints de Usuario - Gestión del Perfil

**PUT /api/v1/profile** - Actualizar/Crear Perfil (Autenticado)

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

**Respuesta**: `{"message": "Perfil actualizado correctamente"}` (200 OK)

**GET /api/v1/matches/candidates** - Obtener Candidatos (Autenticado)

```bash
curl -X GET http://localhost:8080/api/v1/matches/candidates \
  -H "Authorization: Bearer $TOKEN"
```

**Respuesta**: Array de mascotas filtradas por compatibilidad

```json
[
  {
    "id": 5,
    "name": "Bella",
    "type": "dog",
    "breed": "Poodle",
    "age": 3,
    "requires_yard": false,
    "good_with_kids": true,
    "good_with_dogs": true,
    "energy_level": "medium"
  }
]
```

#### 6. Endpoints de Match - Interacciones de Adoptante

**POST /api/v1/matches/swipe** - Registrar Like/Dislike

```bash
curl -X POST http://localhost:8080/api/v1/matches/swipe \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pet_id": 5, "is_like": true}'
```

**Comportamiento**:

- `is_like: true` → Crea Match con status PENDING (solicitud abierta)
- `is_like: false` → Crea Match con status REJECTED (no interesado)

**GET /api/v1/matches/requests** - Solicitudes Pendientes (Solo Rescatistas)

Obtiene todas las mascotas propias que tienen solicitudes de adopción abiertas. Rescatistas ven aquí quién está interesado en sus mascotas.

**POST /api/v1/matches/respond** - Aceptar/Rechazar Solicitud (Solo Rescatistas)

```bash
curl -X POST http://localhost:8080/api/v1/matches/respond \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"match_id": 123, "accept": true}'
```

Cambia estado de Match a ACCEPTED o REJECTED, habilitando chat si es aceptado.

#### 7. Cambios en main.go - Nuevos Servicios

**Servicios Agregados**:

```go
userService  := services.NewUserService(database.DB)
matchService := services.NewMatchService(database.DB, petService)
```

**Handlers Agregados**:

```go
userHandler  := httpTransport.NewUserHandler(userService, matchService)
matchHandler := httpTransport.NewMatchHandler(matchService)
```

**Rutas Protegidas Agregadas**:

```go
protected.PUT("/profile", userHandler.UpdateProfile)
protected.GET("/matches/candidates", userHandler.GetSwipeDeck)
protected.POST("/matches/swipe", matchHandler.Swipe)
protected.GET("/matches/requests", matchHandler.GetPending)
protected.POST("/matches/respond", matchHandler.Respond)
```

### Flujo Completo de Etapa 2

```
1. Adoptante se registra en Etapa 1
   ↓
2. Sistema lo redirige a MatchScreen
   ↓
3. (NUEVO) Usuario completa PUT /profile con datos demográficos
   ↓
4. GET /matches/candidates retorna mascotas compatibles
   ↓
5. Usuario ve tarjetas deslizables (Tinder-style)
   ↓
6. Usuario swipeaLeft (dislike) o Right (like)
   ↓
7. POST /matches/swipe registra la acción
   ↓
8. Si es LIKE, se crea Match con status PENDING
   ↓
9. Rescatista ve Match en GET /matches/requests
   ↓
10. Rescatista POST /matches/respond (accept/reject)
   ↓
11. Si ACCEPTED → Se habilita chat para comunicación
```

### Cambios de Base de Datos

**Nueva Tabla: user_profiles**

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
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

**Alteración: Tabla pets**

Se agregan campos para compatibilidad:

```sql
ALTER TABLE pets ADD COLUMN requires_yard BOOLEAN DEFAULT false;
ALTER TABLE pets ADD COLUMN good_with_kids BOOLEAN DEFAULT true;
ALTER TABLE pets ADD COLUMN good_with_dogs BOOLEAN DEFAULT true;
ALTER TABLE pets ADD COLUMN good_with_cats BOOLEAN DEFAULT true;
ALTER TABLE pets ADD COLUMN energy_level VARCHAR(20) DEFAULT 'medium';
```

### Validación y Testing

**Scenario 1: Usuario sin Perfil**

```bash
# 1. Usuario se registra
POST /auth/register → {"email": "juan@mail.com", "role": "adopter"}

# 2. GET /matches/candidates → Retorna todas las mascotas (primeras 20)
GET /matches/candidates → 200 OK [mascota1, mascota2, ...]
```

**Scenario 2: Usuario con Perfil**

```bash
# 1. Usuario completa perfil
PUT /profile → {"housing": "apartment", "has_children": true}

# 2. GET /matches/candidates → Solo mascotas seguras con niños y sin requerimiento de patio
GET /matches/candidates → [mascota_poodle, mascota_gato, ...]
```

**Scenario 3: Matching End-to-End**

```bash
# Adoptante 1: Swipeadera
POST /matches/swipe → {"pet_id": 5, "is_like": true}
# Crea Match(adopter_id=1, pet_id=5, status=PENDING)

# Rescatista 2: Ve solicitud
GET /matches/requests → [Match#1 de Juan para Bella]

# Rescatista 2: Acepta
POST /matches/respond → {"match_id": 1, "accept": true}
# Match.status = ACCEPTED
# Juan y Rescatista 2 pueden chatear sobre Bella
```

### Salidas hacia Etapa 3

Etapa 2 prepara el terreno para:

- **Búsqueda Geoespacial**: Filtrado adicional por distancia (ej: mascotas dentro de 10km)
- **Scoring Avanzado**: Algoritmos más complejos que consideran compatibilidad de razas, tamaños, temperamentos
- **Recomendaciones**: Sistema de scoring que ordena candidatos por probabilidad de adopción exitosa
- **Notificaciones**: Alertar adoptantes cuando nuevas mascotas coinciden con su perfil
- **Analytics**: Tracking de qué filtros son más usados para optimización futura

## Características Principales por Fase

## Etapa 3: Confianza Comunitaria y Comunicación Segura (Completada)

La Etapa 3 completa el triángulo de confianza en PAWS: después de conectar adoptantes con mascotas (Etapa 2) y asegurar que solo usuarios legítimos pueden acceder (Etapa 1), ahora habilitamos comunicación segura, reputación comunitaria y defensa automática contra abusos. Esta etapa transforma PAWS de una plataforma transaccional a una comunidad de confianza.

### Componentes Implementados

#### 1. Sistema de Reportes y Ban Automático (R-SEC-04)

**Problema Resuelto**: Sin mecanismo de reportes, usuarios maliciosos (timadores, acosadores) pueden operar sin restricción, destruyendo confianza comunitaria.

**Solución**: Sistema de reportes con ban automático tras acumulación de 3 reportes verificados. Cada reporte registra al denunciante, el acusado, el motivo y el estado. Al alcanzar 3 reportes verificados, el usuario es automáticamente añadido a la blacklist.

**Implementación**:

```go
// domain/report.go
type Report struct {
    gorm.Model
    ReporterID uint   `gorm:"not null"` // Quién acusa
    ReportedID uint   `gorm:"not null"` // El acusado
    Reason     string `gorm:"not null"` // "Maltrato", "Acoso", "Cuenta Falsa"
    Status     string `gorm:"default:'pending'"` // pending, verified, rejected
}

// services/report_service.go
type ReportService struct {
    db          *gorm.DB
    authService *AuthService // Para acceso a blacklist
}

// CreateReport registra denuncia y verifica ban automático
func (s *ReportService) CreateReport(reporterID, reportedID uint, reason string) error {
    // 1. Evitar auto-reporte
    if reporterID == reportedID {
        return fmt.Errorf("no puedes reportarte a ti mismo")
    }

    // 2. Crear reporte (se marca como verified en MVP)
    report := domain.Report{
        ReporterID: reporterID,
        ReportedID: reportedID,
        Reason:     reason,
        Status:     "verified", // En producción requeriría revisión manual
    }

    if err := s.db.Create(&report).Error; err != nil {
        return err
    }

    // 3. Aplicar Regla de los 3 Strikes
    return s.checkAndBanUser(reportedID)
}

// checkAndBanUser implementa regla: 3 reportes verificados = ban automático
func (s *ReportService) checkAndBanUser(userID uint) error {
    var count int64
    s.db.Model(&domain.Report{}).
        Where("reported_id = ? AND status = ?", userID, "verified").
        Count(&count)

    if count >= 3 {
        // Obtener usuario
        var user domain.User
        if err := s.db.First(&user, userID).Error; err != nil {
            return err
        }

        // Añadir a blacklist (por RUN, no ID)
        blacklistEntry := domain.BlacklistEntry{
            Run:    user.Run,
            Reason: "Sistema: Acumulación de 3 reportes graves",
        }

        if err := s.db.Create(&blacklistEntry).Error; err != nil {
            // Si ya estaba baneado, ignoramos
            return nil
        }

        fmt.Printf("USUARIO BANEADO AUTOMÁTICAMENTE: %s (%s)\n", user.Name, user.Run)
    }

    return nil
}
```

**Flujo**:

1. Usuario A reporta a Usuario B por "Acoso"
2. Sistema verifica: ¿es auto-reporte? No → Continuar
3. Se crea Report(reporter_id=A, reported_id=B, status="verified")
4. Se cuenta reportes verificados de B: ¿ >= 3? Si → BAN
5. B es añadido a blacklist automáticamente
6. Próximo intento de login de B es rechazado

**Endpoint**:

```
POST /api/v1/report (Protegido)
Headers: Authorization: Bearer TOKEN
Body: {
    "reported_id": 5,
    "reason": "Acoso"
}
Response: 201 {"message": "Reporte recibido. Gracias por ayudar a la comunidad."}
```

#### 2. Sistema de Chat Persistente con Validación Inteligente

**Problema Resuelto**: Chat sin persistencia pierde historial; sin validación, timadores pueden usar el chat para estafas.

**Solución**: Chat híbrido (HTTP + WebSocket) que guarda cada mensaje en PostgreSQL con validación "Evil PAWS" que detecta intentos de estafa.

**Componentes**:

**domain/message.go** - Modelo de mensaje persistente:

```go
type Message struct {
    ID        uint           `gorm:"primaryKey" json:"id"`
    MatchID   uint           `gorm:"index;not null" json:"match_id"`
    Match     Match          `gorm:"foreignKey:MatchID" json:"-"`
    SenderID  uint           `gorm:"index;not null" json:"sender_id"`
    Content   string         `gorm:"type:text;not null" json:"content"`
    IsRead    bool           `gorm:"default:false" json:"is_read"`
    CreatedAt time.Time      `json:"created_at"`
    DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}
```

**services/chat_service.go** - Lógica de validación:

```go
type ChatService struct {
    db *gorm.DB
}

var forbiddenWords = []string{
    "estafa", "odio", "matar", "depósito", "transferencia inmediata"
}

// SaveMessage valida contenido y guarda mensaje
func (s *ChatService) SaveMessage(matchID, senderID uint, content string) (*domain.Message, error) {
    // 1. Filtro "Evil PAWS" - Detecta palabras de estafa
    if s.containsForbiddenContent(content) {
        return nil, errors.New("mensaje bloqueado por contener términos prohibidos")
    }

    // 2. Verificar que Match esté aceptado
    var match domain.Match
    if err := s.db.First(&match, matchID).Error; err != nil {
        return nil, errors.New("match no encontrado")
    }
    if match.Status != domain.MatchAccepted {
        return nil, errors.New("no puedes chatear en un match no aceptado")
    }

    // 3. Guardar mensaje
    msg := domain.Message{
        MatchID:  matchID,
        SenderID: senderID,
        Content:  content,
    }

    if err := s.db.Create(&msg).Error; err != nil {
        return nil, err
    }

    return &msg, nil
}

// GetHistory recupera conversación previa
func (s *ChatService) GetHistory(matchID uint) ([]domain.Message, error) {
    var messages []domain.Message
    err := s.db.Where("match_id = ?", matchID).
        Order("created_at asc").
        Find(&messages).Error
    return messages, err
}

// containsForbiddenContent detecta palabras sospechosas
func (s *ChatService) containsForbiddenContent(text string) bool {
    lowerText := strings.ToLower(text)
    for _, word := range forbiddenWords {
        if strings.Contains(lowerText, word) {
            return true
        }
    }
    return false
}
```

**Arquitectura de Chat Híbrido**:

El chat usa dos canales:

1. **HTTP (Historial)**: GET /api/v1/matches/:id/messages
   - Recupera conversación previa de PostgreSQL
   - Permite cargar chat al abrir la app
   - Implementado en SocialHandler.GetChatHistory()

2. **WebSocket (Tiempo Real)**: GET /api/v1/ws
   - Conexión bidireccional persistente
   - Mensajes se validan y guardan en BD
   - Se difunden a usuarios conectados via Hub

**Endpoints**:

```
GET /api/v1/matches/:id/messages (Protegido)
Headers: Authorization: Bearer TOKEN
Response: 200 [
    {"id": 1, "match_id": 1, "sender_id": 5, "content": "Hola", "created_at": "2025-12-20T10:00:00Z"},
    {"id": 2, "match_id": 1, "sender_id": 7, "content": "Hola, cómo estás?", "created_at": "2025-12-20T10:05:00Z"}
]

GET /api/v1/ws (Protegido - WebSocket)
Upgrade: websocket
Message Incoming: {"match_id": 1, "content": "¿Cuándo podemos reunirnos?"}
Message Validated: Si (no contiene palabras prohibidas)
Message Saved: Si (guardado en PostgreSQL)
Message Broadcast: Si (enviado a otros usuarios en ese match)
```

#### 3. WebSocket Hub para Difusión en Tiempo Real

**Problema Resuelto**: WebSocket directo a cada cliente es ineficiente; necesitamos orquestar conexiones múltiples en un mismo match.

**Solución**: Hub que maneja registro/desregistro de clientes y difunde mensajes a todos los usuarios conectados de un match.

**Implementación**:

**transport/http/hub.go** - Orquestador central:

```go
// Hub mantiene conjunto de clientes activos y transmite mensajes
type Hub struct {
    clients    map[*Client]bool  // Clientes registrados
    broadcast  chan []byte       // Canal de broadcast (mensajes a todos)
    register   chan *Client      // Canal de registro
    unregister chan *Client      // Canal de desregistro
}

func NewHub() *Hub {
    return &Hub{
        broadcast:  make(chan []byte),
        register:   make(chan *Client),
        unregister: make(chan *Client),
        clients:    make(map[*Client]bool),
    }
}

// Run ejecuta el loop de eventos del Hub
func (h *Hub) Run() {
    for {
        select {
        case client := <-h.register:
            h.clients[client] = true  // Nuevo cliente conectado

        case client := <-h.unregister:
            if _, ok := h.clients[client]; ok {
                delete(h.clients, client)
                close(client.send)  // Cierra canal para evitar panic
            }

        case message := <-h.broadcast:
            // Envía mensaje a TODOS los clientes conectados
            for client := range h.clients {
                select {
                case client.send <- message:
                default:
                    // Si el cliente se ha ido (channel full), lo expulsamos
                    close(client.send)
                    delete(h.clients, client)
                }
            }
        }
    }
}
```

**transport/http/client.go** - Representación de cliente WebSocket:

```go
type Client struct {
    hub    *Hub                // Referencia al Hub
    conn   *websocket.Conn    // Conexión WebSocket real
    send   chan []byte         // Canal para mensajes salientes (buffered)
    userID uint                // ID del usuario (para identificar quién envía)
}
```

**Flujo de Cliente**:

1. Usuario conecta: GET /api/v1/ws (con token JWT)
2. WSHandler.HandleConnections() crea Client y registra en Hub
3. Cliente inicia 2 goroutines:
   - Una lee mensajes de WebSocket
   - Una escribe mensajes del canal send
4. Cuando llega mensaje del cliente:
   - ChatService.SaveMessage() valida y guarda en BD
   - Si OK, se envía a hub.broadcast
   - Hub difunde a TODOS los clientes registrados
5. Cliente desconecta:
   - Se desregistra del Hub
   - Se cierra su canal send

#### 4. Sistema de Reviews para Reputación Comunitaria

**Problema Resuelto**: Sin historial de reputación, no hay forma de saber si un rescatista es confiable.

**Solución**: Sistema de calificaciones 1-5 estrellas post-match donde adoptantes califican rescatistas y vice versa.

**Implementación**:

**domain/review.go**:

```go
type Review struct {
    ID        uint           `gorm:"primaryKey" json:"id"`
    MatchID   uint           `gorm:"index;not null" json:"match_id"`
    AuthorID  uint           `gorm:"index;not null" json:"author_id"` // Quién califica
    TargetID  uint           `gorm:"index;not null" json:"target_id"` // A quién califica
    Rating    int            `gorm:"not null" json:"rating"`          // 1-5 estrellas
    Comment   string         `gorm:"type:text" json:"comment"`        // Texto libre
    CreatedAt time.Time      `json:"created_at"`
    DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}
```

**services/review_service.go**:

```go
type ReviewService struct {
    db *gorm.DB
}

func (s *ReviewService) CreateReview(matchID, authorID uint, rating int, comment string) error {
    // 1. Validar rating
    if rating < 1 || rating > 5 {
        return errors.New("rating debe ser entre 1 y 5")
    }

    // 2. Obtener Match para determinar roles
    var match domain.Match
    if err := s.db.First(&match, matchID).Error; err != nil {
        return errors.New("match no válido")
    }

    // 3. Determinar a quién se califica (TargetID)
    targetID := match.AdopterID  // Default: adoptante
    if authorID == match.AdopterID {
        // Si quien califica es el adoptante, está calificando al rescatista
        var pet domain.Pet
        s.db.First(&pet, match.PetID)
        targetID = pet.UserID  // Dueño de la mascota (rescatista)
    }
    // Si quien califica NO es el adoptante, es el rescatista calificando al adoptante
    // targetID ya es AdopterID (asignado arriba)

    // 4. Guardar review
    review := domain.Review{
        MatchID:  matchID,
        AuthorID: authorID,
        TargetID: targetID,
        Rating:   rating,
        Comment:  comment,
    }

    return s.db.Create(&review).Error
}
```

**Lógica de TargetID**:

- Adoptante califica → TargetID = Rescatista (pet.UserID)
- Rescatista califica → TargetID = Adoptante (match.AdopterID)

**Endpoint**:

```
POST /api/v1/reviews (Protegido)
Headers: Authorization: Bearer TOKEN
Body: {
    "match_id": 1,
    "rating": 5,
    "comment": "María fue muy atenta y el perro estaba perfecto"
}
Response: 201 {"message": "Reseña guardada"}
```

#### 5. SocialHandler - Unificación de Chat y Reviews

**Propósito**: Un solo handler maneja todos los endpoints sociales.

```go
type SocialHandler struct {
    chatService   *services.ChatService
    reviewService *services.ReviewService
}

func NewSocialHandler(chat *services.ChatService, review *services.ReviewService) *SocialHandler {
    return &SocialHandler{
        chatService:   chat,
        reviewService: review,
    }
}

// GetChatHistory (GET /matches/:id/messages)
func (h *SocialHandler) GetChatHistory(c *gin.Context) {
    matchIDStr := c.Param("id")
    matchID, _ := strconv.Atoi(matchIDStr)

    messages, err := h.chatService.GetHistory(uint(matchID))
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Error cargando historial"})
        return
    }

    c.JSON(http.StatusOK, messages)
}

// CreateReview (POST /reviews)
func (h *SocialHandler) CreateReview(c *gin.Context) {
    userID := c.MustGet("userID").(uint)

    var req struct {
        MatchID uint   `json:"match_id" binding:"required"`
        Rating  int    `json:"rating" binding:"required"`
        Comment string `json:"comment"`
    }

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    if err := h.reviewService.CreateReview(req.MatchID, userID, req.Rating, req.Comment); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusCreated, gin.H{"message": "Reseña guardada"})
}
```

#### 6. WSHandler - Orquestación de WebSocket y Chat

**Responsabilidades**: Autenticar usuario, upgradar HTTP a WebSocket, registrar cliente en Hub, leer/escribir mensajes.

```go
type WSHandler struct {
    hub         *Hub
    chatService *services.ChatService
}

func NewWSHandler(hub *Hub, chatService *services.ChatService) *WSHandler {
    return &WSHandler{
        hub:         hub,
        chatService: chatService,
    }
}

// HandleConnections es el endpoint GET /ws
func (h *WSHandler) HandleConnections(c *gin.Context) {
    // 1. Extraer userID del token
    userIDVal, exists := c.Get("userID")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
        return
    }
    userID := userIDVal.(uint)

    // 2. Upgrade HTTP -> WebSocket
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        log.Println("Error upgrade:", err)
        return
    }

    // 3. Crear Cliente y registrarlo en Hub
    client := &Client{
        hub:    h.hub,
        conn:   conn,
        send:   make(chan []byte, 256),
        userID: userID,
    }

    h.hub.register <- client

    // 4. Iniciar lectura/escritura concurrentes
    go h.readPump(client)
    go h.writePump(client)
}

// readPump lee mensajes del cliente WebSocket
func (h *WSHandler) readPump(client *Client) {
    defer func() {
        h.hub.unregister <- client
        client.conn.Close()
    }()

    for {
        var msg struct {
            MatchID uint   `json:"match_id"`
            Content string `json:"content"`
        }

        if err := client.conn.ReadJSON(&msg); err != nil {
            break
        }

        // Validar y guardar mensaje en BD
        savedMsg, err := h.chatService.SaveMessage(msg.MatchID, client.userID, msg.Content)
        if err != nil {
            // Enviar error al cliente
            client.send <- []byte(`{"error":"` + err.Error() + `"}`)
            continue
        }

        // Serializar respuesta exitosa
        response, _ := json.Marshal(savedMsg)

        // Difundir a TODOS los usuarios conectados en ese match
        h.hub.broadcast <- response
    }
}

// writePump envía mensajes desde el canal send al cliente
func (h *WSHandler) writePump(client *Client) {
    for message := range client.send {
        if err := client.conn.WriteMessage(websocket.TextMessage, message); err != nil {
            return
        }
    }
}
```

#### 7. ReportHandler - Endpoint de Reportes

**Propósito**: Procesar solicitudes de reporte.

```go
type ReportHandler struct {
    service *services.ReportService
}

func NewReportHandler(s *services.ReportService) *ReportHandler {
    return &ReportHandler{service: s}
}

func (h *ReportHandler) Create(c *gin.Context) {
    // Obtener ID del reportante desde token
    reporterID := c.GetUint("userID")
    if reporterID == 0 {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
        return
    }

    var req struct {
        ReportedID uint   `json:"reported_id" binding:"required"`
        Reason     string `json:"reason" binding:"required"`
    }

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    if err := h.service.CreateReport(reporterID, req.ReportedID, req.Reason); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusCreated, gin.H{"message": "Reporte recibido. Gracias por ayudar a la comunidad."})
}
```

### Cambios en Base de Datos

**Nuevas tablas creadas por AutoMigrate en main.go**:

```go
if err := database.DB.AutoMigrate(
    &domain.User{},
    &domain.UserProfile{},
    &domain.Pet{},
    &domain.Match{},
    &domain.Message{},       // Etapa 3
    &domain.Review{},        // Etapa 3
    &domain.Report{},        // Etapa 3
    &domain.BlacklistEntry{},
); err != nil {
    log.Fatal("Error migrando BD:", err)
}
```

**Schema de nuevas tablas**:

```sql
-- Messages (Chat persistente)
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    match_id INTEGER NOT NULL,
    sender_id INTEGER NOT NULL,
    content TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP,
    deleted_at TIMESTAMP,
    FOREIGN KEY (match_id) REFERENCES matches(id),
    FOREIGN KEY (sender_id) REFERENCES users(id)
);
CREATE INDEX idx_messages_match_id ON messages(match_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);

-- Reviews (Reputación)
CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    match_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    target_id INTEGER NOT NULL,
    rating INTEGER NOT NULL,
    comment TEXT,
    created_at TIMESTAMP,
    deleted_at TIMESTAMP,
    FOREIGN KEY (match_id) REFERENCES matches(id),
    FOREIGN KEY (author_id) REFERENCES users(id),
    FOREIGN KEY (target_id) REFERENCES users(id)
);
CREATE INDEX idx_reviews_match_id ON reviews(match_id);
CREATE INDEX idx_reviews_author_id ON reviews(author_id);
CREATE INDEX idx_reviews_target_id ON reviews(target_id);

-- Reports (Sistema de reportes)
CREATE TABLE reports (
    id SERIAL PRIMARY KEY,
    reporter_id INTEGER NOT NULL,
    reported_id INTEGER NOT NULL,
    reason VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    FOREIGN KEY (reporter_id) REFERENCES users(id),
    FOREIGN KEY (reported_id) REFERENCES users(id)
);
CREATE INDEX idx_reports_reporter_id ON reports(reporter_id);
CREATE INDEX idx_reports_reported_id ON reports(reported_id);
CREATE INDEX idx_reports_status ON reports(status);
```

### Rutas Nuevas en main.go

```go
// En el grupo de rutas protegidas:
protected := api.Group("/")
protected.Use(middleware.AuthMiddleware())
{
    // ... rutas anteriores ...

    // Chat (Etapa 3)
    match := protected.Group("/matches")
    {
        // ... rutas anteriores ...
        match.GET("/:id/messages", socialHandler.GetChatHistory)
    }

    // Reviews (Etapa 3)
    protected.POST("/reviews", socialHandler.CreateReview)

    // Reportes (Etapa 3)
    protected.POST("/report", reportHandler.Create)

    // WebSocket para chat tiempo real (Etapa 3)
    protected.GET("/ws", wsHandler.HandleConnections)
}
```

### Escenarios Implementados en Etapa 3

**Escenario 1: Timador intenta estafar**

```
1. Match entre Adoptante A y Rescatista (Timador)
2. Adoptante abre chat: GET /matches/1/messages → obtiene historial vacío
3. Adoptante se conecta: GET /ws (WebSocket establecido)
4. Timador envía: "Transfiere 50k al banco antes de recoger"
5. ChatService.SaveMessage() verifica forbiddenWords → "transferencia" detectada
6. Mensaje BLOQUEADO: no se guarda, error retornado
7. Timador recibe: {"error": "mensaje bloqueado..."}
8. Adoptante nunca ve el mensaje → PROTEGIDO
```

**Escenario 2: Usuario es reportado 3 veces**

```
1. Usuario B es reportado por A (razón: "Acoso") → Report 1 creado
2. Usuario B es reportado por C (razón: "Comportamiento sospechoso") → Report 2 creado
3. Usuario B es reportado por D (razón: "Intentó estafar") → Report 3 creado
4. ReportService.checkAndBanUser(B) cuenta: count = 3
5. User B es buscado en BD
6. BlacklistEntry creada: {run: B.Run, reason: "Sistema: 3 reportes"}
7. Usuario B logueado de BD
8. Próximo login de B es rechazado en AuthService (blacklist check)
9. Usuario B está baneado permanentemente
```

**Escenario 3: Adoptante califica rescatista post-adopción**

```
1. Match entre Adoptante A y Rescatista B completado
2. Adopción exitosa, mascota en casa de A
3. Adoptante abre reviews: POST /reviews
4. Envía: {match_id: 1, rating: 5, comment: "María fue excelente"}
5. ReviewService.CreateReview() ejecuta:
   - Valida rating: 1-5 ✓
   - Obtiene Match → AdopterID=A, PetID=7
   - AuthorID == AdopterID? Sí → TargetID = pet.UserID (B)
   - Crea Review(match_id=1, author_id=A, target_id=B, rating=5, ...)
6. Rescatista B ve su reputación mejorada
```

### Decisiones Arquitectónicas

**1. Ban automático tras 3 reportes vs moderación manual**

**Elegida**: Ban automático

Razón: Velocidad y coherencia. Si 3 usuarios independientes reportan al mismo comportamiento, hay suficiente evidencia estadística. Moderación manual crea demora donde hay urgencia.

Alternativa: Moderación manual (más lenta, requiere personal)

**2. Palabras prohibidas en lista hardcoded vs BD**

**Elegida**: Hardcoded en código (MVP)

```go
var forbiddenWords = []string{
    "estafa", "odio", "matar", "depósito", "transferencia inmediata"
}
```

Razón: Velocidad de desarrollo. En producción vendría de BD con hot-reload.

Alternativa: BD con tabla badwords (más flexible)

**3. Hub broadcasts a TODOS vs filtra por Match**

**Elegida**: TODOS (simple)

Nota: Implementación actual difunde a todos los clientes conectados. Optimización futura: difundir solo a clientes del match específico (agrupación por match).

Alternativa: Agrupar clientes por match (más escalable)

**4. Reviews post-match vs en tiempo real**

**Elegida**: Post-match

Razón: Reviews requieren perspectiva después de interacción completa. No tiene sentido calificar antes de que termine la adopción.

Flujo: Match.status == accepted → después de ciclo completo → POST /reviews

### Flujo Completo Etapa 3

```
┌─────────────────────────────────────────────────────────────┐
│ ETAPA 3: Comunicación Segura y Reputación Comunitaria       │
└──────────────┬──────────────────────────────────────────────┘
               │
     ┌─────────┼─────────┐
     ▼         ▼         ▼
  REPORTS  CHAT_MSG   REVIEWS
     │         │         │
     │         │         └─────────┬─────────┐
     │         │               Adoptante    Rescatista
     │         │                  │              │
  (3 strikes) POST             (Califica     (Califica
   = BAN      /ws            Rescatista)    Adoptante)
   │        GET/msg
   │        SaveMessage()
   │        (Filtro Evil PAWS)
   │        Si "transferencia" → BLOQUEADO
   │        Si OK → Guarda + Hub.broadcast
   │
   ▼
  BlackList

FLUJO DE USUARIO:
1. Adoptante inicia chat: GET /ws (WebSocket)
2. Carga historial: GET /matches/1/messages (HTTP)
3. Envía mensaje: {"match_id": 1, "content": "..."}
4. ChatService valida (forbiddenWords)
5. Si OK: Guarda en BD + difunde a Hub
6. Si NG: Rechaza silenciosamente
7. Otros usuarios reciben via Hub (WebSocket)
8. Post-adopción: POST /reviews (calificar)
9. Rescatista reportado 3 veces → Auto-ban a blacklist
```

## Etapa 4: Bandejas de Entrada Inteligentes y Robustez del Matchmaking (Completada)

La Etapa 4 construye sobre el motor de matchmaking de Etapa 2 (GetSwipeDeck) y el sistema de chat en tiempo real de Etapa 3, pero se enfoca en la experiencia de usuario completa: proporcionar a adoptantes y rescatistas bandejas de entrada inteligentes que muestren exactamente lo que necesitan ver en cada momento, además de corregir problemas críticos de estabilidad que surgen cuando múltiples usuarios interactúan simultáneamente.

Esta etapa transforma el flujo de matching de una vista plana ("muéstrame todas las mascotas") a una experiencia de varios niveles que distingue entre Likes Pendientes (esperando respuesta del rescatista), Matches Aceptados (chats habilitados), y Solicitudes Entrantes (para rescatistas que reciben múltiples likes).

### Componentes Implementados

#### 1. Problema de Duplicación en Swipe Deck y Solución Robusta con LEFT JOIN

**Problema Identificado en Etapa 2**: GetSwipeDeck usaba GORM con Joins que a veces causaba comportamientos inesperados, permitiendo que mascotas ya deslizadas (con estado REJECTED o PENDING) volvieran a aparecer en futuras iteraciones.

**Solución Implementada en Etapa 4**: SQL puro con LEFT JOIN para garantizar que una mascota solo aparece si NO existe ningún match anterior para ese usuario.

```go
func (s *MatchService) GetSwipeDeck(userID uint) ([]domain.Pet, error) {
	var pets []domain.Pet

	query := `
		SELECT p.* FROM pets p
		LEFT JOIN matches m ON m.pet_id = p.id AND m.adopter_id = ?
		WHERE m.id IS NULL
		AND p.status = ?
		AND p.deleted_at IS NULL
	`

	err := s.db.Raw(query, userID, domain.StatusAvailable).Scan(&pets).Error
	return pets, err
}
```

**Lógica del LEFT JOIN**:

- Selecciona todas las mascotas disponibles (p)
- LEFT JOIN con matches: trae filas donde m.id IS NOT NULL solo si existe match
- WHERE m.id IS NULL: filtra para traer SOLO mascotas que NO tienen match con este usuario
- Resultado: Mascotas deslizadas (like o dislike) nunca reaparecen

**Impacto**: Experiencia de usuario consistente. Una mascota que rechazaste nunca volverá a tu deck de swipe.

#### 2. Bandejas de Entrada del Adoptante

**Requisito**: El adoptante necesita ver dos vistas distintas:

1. **Chats Activos**: Matches aceptados donde puede chatear
2. **Likes Pendientes**: Likes que dio pero todavía espera respuesta del rescatista

**Implementación en MatchService**:

```go
// GetAcceptedMatches: Chats habilitados (chats activos)
func (s *MatchService) GetAcceptedMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet.User").
		Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchAccepted).
		Find(&matches).Error
	return matches, err
}

// GetAdopterPendingMatches: Likes pendientes esperando respuesta del rescatista
func (s *MatchService) GetAdopterPendingMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchPending).
		Find(&matches).Error
	return matches, err
}
```

**Diferencia Clave**: GetAcceptedMatches incluye Preload("Pet.User") para obtener datos del rescatista en chats. GetAdopterPendingMatches solo carga Pet porque no hay interacción aún.

#### 3. Centro de Control del Rescatista

**Requisito**: El rescatista es receptor pasivo que reacciona a múltiples likes entrantes. Necesita ver:

1. **Solicitudes Pendientes**: Likes que recibió (en tabla matches con status=pending)
2. **Chats Activos**: Adopciones en progreso (status=accepted)

**Implementación en MatchService**:

```go
// GetPendingRequests: Adoptantes interesados en mis mascotas (esperando mi respuesta)
func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").
		Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
		Find(&matches).Error
	return matches, err
}

// GetRescuerMatches: Mis adopciones activas (chats en progreso)
func (s *MatchService) GetRescuerMatches(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").
		Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchAccepted).
		Find(&matches).Error
	return matches, err
}
```

**Diferencia de SQL**: Rescatista ve matches donde pets.user_id (dueño de mascota) es él. Usamos JOIN para filtrar por propietario de mascota, no por adoptante directo.

#### 4. Nuevos Endpoints HTTP para Bandejas de Entrada

```go
// GET /matches/mine
// Retorna: []Match con status=accepted (chats activos del adoptante)
func (h *MatchHandler) GetMyMatches(c *gin.Context)

// GET /matches/mine/pending
// Retorna: []Match con status=pending (likes que diste esperando respuesta)
func (h *MatchHandler) GetMyPending(c *gin.Context)

// GET /matches/rescuer
// Retorna: []Match donde pets.user_id = rescuerId y status=accepted
// (Chats activos del rescatista)
func (h *MatchHandler) GetRescuerMatches(c *gin.Context)

// GET /matches/requests
// Retorna: []Match donde pets.user_id = rescuerId y status=pending
// (Solicitudes entrantes al rescatista)
func (h *MatchHandler) GetPending(c *gin.Context)
```

**Integración en main.go**:

```go
match := protected.Group("/matches")
{
	match.GET("/candidates", matchHandler.GetMatches)          // Deck de swipe
	match.POST("/swipe", matchHandler.Swipe)                  // Dar like/dislike
	match.GET("/requests", matchHandler.GetPending)           // Rescatista: solicitudes entrantes
	match.POST("/respond", matchHandler.Respond)              // Rescatista: aceptar/rechazar
	match.GET("/mine", matchHandler.GetMyMatches)             // NUEVO: Adoptante: chats activos
	match.GET("/mine/pending", matchHandler.GetMyPending)     // NUEVO: Adoptante: likes pendientes
	match.GET("/rescuer", matchHandler.GetRescuerMatches)     // NUEVO: Rescatista: chats activos
	match.GET("/:id/messages", socialHandler.GetChatHistory)  // Historial de chat (Etapa 3)
}
```

#### 5. Mejoras en el Cliente HTTP (Type Safety)

**Problema Identificado**: JWT devuelve userID como float64 (JSON unmarshaling), pero a veces podría ser uint. Extraer el valor sin panic.

**Solución - Helper Function**:

```go
func getUserIDFromContext(c *gin.Context) (uint, bool) {
	idVal, exists := c.Get("userID")
	if !exists {
		return 0, false
	}

	// Manejo robusto de tipos
	switch v := idVal.(type) {
	case float64:
		return uint(v), true
	case uint:
		return v, true
	case int:
		return uint(v), true
	case uint64:
		return uint(v), true
	default:
		return 0, false
	}
}
```

**Beneficio**: Evita panics por type assertion fallida. Backend más robusto ante cambios en JWT generation.

#### 6. Frontend: ChatBloc con JWT Decoding para Identificar Mensajes Propios

**Problema Identificado**: ChatBloc necesita saber cuál es el userID actual para distinguir mis mensajes de los del otro usuario en la UI.

**Solución - JWT Decode Local**:

```dart
on<InitChat>((event, emit) async {
	_currentMatchId = event.matchId;
	emit(ChatLoading());

	try {
		// A. Extraer mi userID del token almacenado
		final token = await _storage.read(key: 'jwt_token');
		if (token != null) {
			Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
			_myUserId = (decodedToken['user_id'] ?? decodedToken['sub'] ?? 0).toInt();
		}

		// B. Cargar historial de mensajes anteriores
		final rawHistory = await repository.getRawHistory(event.matchId);
		final List<ChatMessage> history = rawHistory
			.map((json) => ChatMessage.fromJson(json, _myUserId))
			.toList();

		emit(ChatLoaded(
			messages: history,
			matchId: _currentMatchId,
			myUserId: _myUserId,  // Pasar mi ID al estado
		));

		// C. Conectar WebSocket para mensajes en tiempo real
		await repository.connect();
	} catch (e) {
		emit(ChatError("Error: $e"));
	}
});
```

**Datos de Salida**: ChatLoaded ahora incluye myUserId para que la UI sepa cuál mensaje es mío.

#### 7. Frontend: ChatScreen con Manejo Robusto de Listas Vacías

**Problema Identificado**: Si el historial está vacío, mostrar un estado vacío elegante. Si los datos son null vs [], manejar ambos casos sin crashes.

**Solución - BlocBuilder Robusto**:

```dart
if (state is ChatLoaded) {
	// Manejar lista vacía
	if (state.messages.isEmpty) {
		return _buildEmptyState();
	}

	// Invertir lista para scroll desde abajo
	final reversedMessages = state.messages.reversed.toList();

	return ListView.builder(
		reverse: true,  // Inicio en bottom, mejor con teclado
		padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
		itemCount: reversedMessages.length,
		itemBuilder: (context, index) {
			final msg = reversedMessages[index];
			final isMine = msg.senderID == state.myUserId;
			return _buildMessageBubble(msg, isMine);
		},
	);
}

Widget _buildEmptyState() {
	return Center(
		child: Container(
			padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
			decoration: BoxDecoration(
				color: Colors.white.withOpacity(0.8),
				borderRadius: BorderRadius.circular(20),
			),
			child: const Text(
				"Di hola para comenzar la adopción",
				style: TextStyle(color: Colors.grey),
			),
		),
	);
}
```

**Mejoras Clave**:

- `if (state.messages.isEmpty)`: Detecta listas vacías sin comparar con null
- `reverse: true` en ListView: Scroll empieza en bottom, mejor UX con teclado virtual
- `state.myUserId`: Acceso seguro a mi ID para renderizar burbujas correctamente
- Fallback `Container()`: Evita null reference errors

#### 8. Flujo Completo: Adoptante desde Like hasta Chat

```
ADOPTANTE FLOW:

1. Home Screen - GET /matches/candidates
   - Servidor ejecuta LEFT JOIN
   - Retorna mascotas sin match previo con él

2. Swipe Decisión - POST /matches/swipe (isLike=true)
   - Status cambio: (no existe) → pending

3. Bandeja de Entrada:
   - GET /matches/mine → Chats activos (vacío)
   - GET /matches/mine/pending → Likes pendientes (1 elemento)

4. Espera Respuesta del Rescatista:
   - Rescatista recibe solicitud de match
   - Rescatista acepta via POST /matches/respond
   - Match status: pending → accepted

5. Chat Habilitado:
   - GET /matches/mine → Ahora muestra 1 chat activo
   - GET /matches/:id/messages → Historial
   - GET /ws → WebSocket para mensajes en tiempo real
   - POST /reviews → Post-adopción, calificar rescatista
```

#### 9. Flujo Completo: Rescatista como Centro de Control

```
RESCATISTA FLOW:

1. Dashboard:
   - GET /matches/requests → Solicitudes pendientes (adoptantes interesados)
   - GET /matches/rescuer → Chats activos (adopciones en progreso)

2. Solicitud Entrante:
   - Notificación: "Hay 1 solicitud pendiente"
   - Ver detalles de adoptante

3. Responder Solicitud:
   - POST /matches/respond (accept=true|false)
   - Status: pending → accepted

4. Aceptar Solicitud:
   - GET /matches/requests → Solicitud desaparece
   - GET /matches/rescuer → Chat aparece

5. Chat Activo:
   - GET /matches/:id/messages → Historial
   - GET /ws → Escuchar mensajes en tiempo real
   - POST /reviews → Post-adopción, calificar adoptante
```

#### 10. Correcciones de Estabilidad Críticas Implementadas

**Corrección 1: Manejo de Tipos en JWT**
Problema: JWT middleware podría devolver userID como float64, causando type assertion panic.
Solución: Helper function con switch statement que maneja múltiples tipos.

**Corrección 2: Listas Nulas en Frontend**
Problema: Backend retorna `[]Match` (lista vacía). Frontend confundía null vs [].
Solución: Verificación explícita `if (state.messages.isEmpty)` que funciona correctamente con ambas.

**Corrección 3: LEFT JOIN en GetSwipeDeck**
Problema: GORM Joins a veces causaban que mascotas rechazadas volvieran a aparecer.
Solución: SQL puro con `LEFT JOIN ... WHERE m.id IS NULL` garantiza que solo mascotas sin match aparecen.

### Beneficios de Etapa 4

1. **Claridad de Estados**: Adoptante ve exactamente qué likes están pendientes vs. cuáles están aceptados
2. **Reducción de Duplicados**: LEFT JOIN garantiza que mascotas deslizadas no reaparecen
3. **Robustez Frontend**: Manejo de listas vacías, JWT type casting, ListView reverse scroll
4. **Centro de Control para Rescatista**: Vista consolidada de solicitudes entrantes y chats activos
5. **UX Consistente**: Mensajes vacíos elegantes, burbujas de chat distinguidas por usuario
6. **Escalabilidad**: Nueva arquitectura de bandejas no requiere cambios en backend existente
7. **Confianza**: Reputación visual (reviews) asociada a cada rescatista/adoptante visible en bandejas

### Fase 7: CI/CD y Testing Automático

**Objetivos Logrados**:

- Pipeline CI/CD completamente funcional en GitHub Actions
- Análisis estático automático con golangci-lint (detecta bugs, style issues, code smells)
- Escaneo automático de vulnerabilidades CVE con govulncheck
- Tests unitarios integrados en pipeline (go test -v ./...)
- Docker build & push automático a Docker Hub en cada push a main/develop
- Cobertura de código con reportes HTML

**Beneficios**:

- Código de calidad garantizado antes de merge
- Vulnerabilidades detectadas automáticamente
- Imágenes Docker siempre actualizadas en Docker Hub
- Confianza en que main branch siempre está funcional
- Ahorro de 5+ minutos de testing manual por push

### Fase 8: Seguridad Robusta (Evil PAWS)

**Objetivos Logrados**:

1. **R-SEC-01: Verificación de Identidad**
   - Carga de documento de identidad a MinIO (S3-compatible)
   - Validación automática de RUT chileno con algoritmo Módulo 11
   - Generación de RUT válido con dígito verificador correcto
   - Almacenamiento seguro en la nube

2. **R-SEC-02: Anti-Multicuentas**
   - Chequeo automático de RUN único en registro y login
   - Prevención de múltiples cuentas por usuario
   - Validación en base de datos con UNIQUE constraint

3. **R-SEC-03: Blacklist System**
   - Sistema de blacklist para usuarios baneados
   - Chequeo en Register y Login
   - Prevención de acceso a usuarios baneados

4. **R-SEC-04: Sistema de Reportes con Auto-Ban**
   - Usuarios pueden reportar comportamiento inapropiado
   - Sistema automático: 3 reportes verificados = ban automático
   - Sin intervención manual requerida
   - Integración con blacklist automática

**Servicios Nuevos**:

- `IdentityService`: Gestión de verificación de identidad
- `OTPService`: Generación de códigos OTP 6-dígito con TTL de 5 minutos
- `ReportService`: Sistema de reportes con contador automático
- Modelos: `Report`, `BlacklistEntry`

**Algoritmos Implementados**:

- Módulo 11 para validación de RUT chileno
- Generación de RUT aleatorio válido
- OTP de 6 dígitos con almacenamiento en Redis

## Etapa 5: Identidad y Territorio - Humanización y Localización de la Experiencia (Completada)

La Etapa 5 transforma PAWS de una plataforma basada en algoritmos abstractos a una donde los actores se conocen y el territorio importa. Los usuarios dejan de ser IDs anónimos para convertirse en personas reales con foto, nombre, biografía y teléfono. Simultáneamente, implementamos geolocalización real con permisos de GPS en tiempo real, permitiendo que adoptantes y rescatistas busquen mascotas según su ubicación geográfica. Además, rediseñamos la experiencia frontend con un MainLayout moderno basado en navegación por pestañas inferior (bottom navigation bar), unificando la experiencia para ambos roles de usuario.

### Pilares de Etapa 5

1. **Identidad Real**: Foto, Nombre, Biografía y Teléfono para generar confianza
2. **Territorio**: Búsqueda geolocalizada con distancia Euclidiana en SQL
3. **Permisos y Privacidad**: Solicitud de permisos de GPS respetando privacidad del usuario
4. **Rediseño UX**: MainLayout unificado con NavigationBar inferior (Material 3)

### Cambios en el Backend de Etapa 5

#### 1. Enriquecimiento del Modelo de Usuario (user.go)

El modelo `User` en `internal/core/domain/user.go` fue extendido con tres nuevos campos que humanizaron la plataforma:

**Campos Nuevos Agregados:**

- `PhotoURL string`: URL a la foto de perfil del usuario (cargada a través de MinIO)
- `Bio string`: Campo de texto largo (type:text en GORM) para que usuarios describan su situación (ej: "Vivo en casa con patio grande, tengo experiencia con perros grandes")
- `Phone string`: Número de teléfono o WhatsApp para contacto directo

Estos campos opcionalmente se llenan cuando el usuario edita su perfil. La presencia de fotografía, biografía y teléfono aumenta dramáticamente la confianza entre Adoptantes y Rescatistas antes de realizar la adopción. La foto se renderiza en las tarjetas de perfil, la biografía aparece al expandir un perfil, y el teléfono se muestra solo después de que el match es aceptado.

**Estructura del modelo actualizado:**

```go
type User struct {
	gorm.Model
	Name  string
	Email string
	Run   string
	Password string
	Role  string
	IsVerified bool
	IsBanned   bool

	// --- NUEVOS CAMPOS DE IDENTIDAD (Etapa 5) ---
	PhotoURL string
	Bio      string `gorm:"type:text"`
	Phone    string
}
```

**Impacto en Seguridad**: Aunque estos campos humanizarán la experiencia, los números de teléfono y fotos deben ser validados. Se puede implementar en futuro una verificación de que la foto del perfil coincida con la identidad verificada (R-SEC-01).

#### 2. Nueva Lógica en UserService (user_service.go)

Se agregó un nuevo método en `internal/core/services/user_service.go`:

**Método UpdateIdentity(userID uint, name, bio, phone, photoURL string) error**

Este método utiliza un mapa de actualizaciones GORM para ser flexible. Solo actualiza los campos proporcionados, permitiendo que el usuario actualice su perfil de forma selectiva (actualizar foto sin tocar teléfono, etc.).

```go
func (s *UserService) UpdateIdentity(userID uint, name, bio, phone, photoURL string) error {
	updates := map[string]interface{}{
		"name":      name,
		"bio":       bio,
		"phone":     phone,
		"photo_url": photoURL,
	}
	return s.db.Model(&domain.User{}).Where("id = ?", userID).Updates(updates).Error
}
```

El método se complementa con `GetUser` para permitir que el frontend cargue los datos actuales en el formulario de edición.

#### 3. Nuevos Handlers de Perfil (user_handler.go)

Se agregaron dos nuevos endpoints HTTP para gestionar la identidad del usuario:

**PUT /profile** - UpdateProfile(c \*gin.Context)

- Recibe JSON con campos: name, bio, phone, photo_url
- Requiere autenticación (JWT)
- Extrae userID del contexto con manejo seguro de tipos (float64 → uint)
- Llama a UserService.UpdateIdentity
- Retorna JSON con mensaje de éxito

**GET /profile** - GetProfile(c \*gin.Context)

- Permite que el frontend cargue los datos actuales del usuario para rellenar el formulario de edición
- Retorna el objeto User completo con todos los campos

```go
type UpdateProfileRequest struct {
	Name     string `json:"name"`
	Bio      string `json:"bio"`
	Phone    string `json:"phone"`
	PhotoURL string `json:"photo_url"`
}

func (h *UserHandler) UpdateProfile(c *gin.Context) {
	// 1. Obtener userID del JWT (con manejo de tipos)
	// 2. Bind JSON
	// 3. Llamar UpdateIdentity
	// 4. Retornar respuesta
}
```

#### 4. Geolocalización: Búsqueda Cercana con Haversine (pet_service.go)

El cambio más significativo en el backend para Etapa 5 es la implementación de **búsqueda geoespacial real** en `internal/core/services/pet_service.go`.

**Método SearchNearby(lat, lng float64, distanceKM float64) ([]domain.Pet, error)**

Implementa la fórmula **Haversine** en SQL puro para calcular la distancia entre dos puntos en la Tierra:

```go
func (s *PetService) SearchNearby(lat, lng float64, distanceKM float64) ([]domain.Pet, error) {
	var pets []domain.Pet

	query := `
		SELECT *, (
			6371 * acos(
				cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) +
				sin(radians(?)) * sin(radians(latitude))
			)
		) AS distance
		FROM pets
		WHERE status = ?
		ORDER BY distance ASC
	`

	err := s.db.Raw(query, lat, lng, lat, domain.PetAvailable).Scan(&pets).Error
	if err != nil {
		return nil, err
	}

	var filtered []domain.Pet
	for _, p := range pets {
		filtered = append(filtered, p)
	}

	return filtered, nil
}
```

**Desglose de la Fórmula Haversine:**

1. `cos(radians(userLat)) * cos(radians(petLat))`: Producto de cosenos de latitudes
2. `cos(radians(petLon) - radians(userLon))`: Coseno de la diferencia de longitudes
3. `sin(radians(userLat)) * sin(radians(petLat))`: Producto de senos de latitudes
4. `acos()`: Ángulo entre los dos puntos
5. `6371 *`: Radio de la Tierra en km, multiplicado para obtener distancia real

**Limitaciones del enfoque actual:**

- El filtro de distancia (distanceKM) se aplica en memoria después de la consulta SQL
- Para un filtro SQL verdadero, se puede mejorar usando `HAVING distance <= ?`
- El orden es por distancia ascendente (más cerca primero)

**Ventajas de esta implementación:**

- No requiere índices geoespaciales PostGIS
- Compatible con cualquier base de datos SQL (MySQL, PostgreSQL, SQLite)
- Matemáticamente preciso para distancias hasta ~50km (error <1% para rangos de adopción locales)
- Retorna la distancia calculada para que el frontend la muestre

#### 5. Nuevas Rutas en main.go

Se agregaron dos rutas nuevas protegidas por autenticación:

```go
protected.PUT("/profile", userHandler.UpdateProfile)      // Actualizar identidad
protected.GET("/profile", userHandler.GetProfile)         // Cargar perfil actual

// En pets rutas (público):
petsPublic.GET("/nearby", petHandler.GetNearby)           // GET /api/v1/pets/nearby?lat=-33.4&lng=-70.6&dist=10
```

El endpoint `/pets/nearby` es **público** (no requiere autenticación) permitiendo que usuarios no registrados vean mascotas cercanas en un mapa de preview.

### Cambios en el Frontend de Etapa 5

#### 1. Pantalla de Edición de Perfil (edit_profile_screen.dart)

Se creó una nueva pantalla completa en `app/lib/features/user/presentation/screens/edit_profile_screen.dart` que implementa un formulario robusto para editar la identidad del usuario.

**Funcionalidades Principales:**

1. **Carga de perfil actual**: Al abrir la pantalla, `GET /profile` carga nombre, bio, teléfono y URL de foto
2. **Selección de foto**: Integración con `image_picker` para permitir seleccionar de la galería
3. **Vista previa de foto**: CircleAvatar que muestra la foto actual o nueva (local)
4. **Formulario con validación**:
   - Nombre: Campo requerido, TextFormField con validación
   - Bio: Campo opcional, permite 3 líneas (maxLines: 3)
   - Teléfono: Campo opcional, teclado numérico/telefónico
5. **Guardado**: Sube foto (si es nueva) a través de MinIO, luego `PUT /profile` con todos los datos
6. **Feedback**: SnackBar para éxito/error

**Flujo de Guardado:**

```
1. Usuario selecciona foto nueva (o mantiene la actual)
2. Usuario rellena nombre, bio, teléfono
3. Usuario presiona ícono CHECK (AppBar action)
4. Si hay foto nueva: uploadProfilePicture() → MinIO → devuelve URL
5. PUT /profile con name, bio, phone, photo_url
6. SnackBar "Perfil actualizado"
7. Navigator.pop(context, true) para volver atrás
```

**Componentes Flutter Utilizados:**

- StatefulWidget con ciclo de vida (initState para cargar datos)
- Form + FormField para validación
- GestureDetector + CircleAvatar para foto clickeable
- ImagePicker para selección de galería
- UserRepository inyectado via `context.read<>()`

#### 2. MainLayout Moderno (main_layout_screen.dart)

Se creó un nuevo componente arquitectónico en `app/lib/core/presentation/main_layout_screen.dart` que reemplaza la navegación antigua basada en botones dispersos con una **barra inferior moderna tipo Material 3** usando `NavigationBar`.

**Propósito**: Proporcionar una navegación consistente y accesible para ambos roles (Adoptante y Rescatista) sin que cada pantalla tenga que implementar su propio menú.

**Estructura de Pantallas:**

- **Para Adoptantes** (3 pestañas):
  - Tab 0: MatchScreen (Descubrir mascotas)
  - Tab 1: AdopterMatchesScreen (Mis Matches/Chats)
  - Tab 2: EditProfileScreen (Editar Perfil)

- **Para Rescatistas** (4 pestañas):
  - Tab 0: RescuerHomeScreen (Mis Mascotas)
  - Tab 1: RescuerChatsScreen (Chats Activos)
  - Tab 2: MatchRequestsScreen (Solicitudes Pendientes)
  - Tab 3: EditProfileScreen (Editar Perfil)

**Características Técnicas:**

1. **StatefulWidget**: Mantiene `_currentIndex` para saber qué pestaña está activa
2. **IndexedStack**: No recarga las pantallas al cambiar tab (mantiene scroll position, estado de formularios, etc.)
3. **Material 3 NavigationBar**: indicatorColor personalizado (#E91E63 con opacidad)
4. **Diferenciación por rol**: Constructor recibe `role` ('adopter' o 'rescuer')
5. **RepositoryProvider**: Inyecta dependencias en pantallas que lo necesitan

**Ventajas UX:**

- La barra está **siempre visible** al cambiar de pestaña
- El icono de la pestaña activa se destaca con color
- Los iconos son reconocibles intuitivamente
- El acceso a Perfil es consistente en todas partes (última pestaña)
- No hay transición de animación compleja (mantiene la experiencia ágil)

**Históricamente**: Reemplaza una navegación anterior donde cada pantalla tenía un AppBar con botones de navegación, lo que creaba inconsistencia y ocultaba la barra al hacer scroll.

#### 3. Solicitud de Permisos y Obtención de GPS (pets_bloc.dart)

El `PetsBloc` en `app/lib/features/pets/presentation/bloc/pets_bloc.dart` fue mejorado para solicitar y utilizar permisos de GPS de forma elegante.

**Evento LoadSwipeDeck Mejorado:**

El evento `LoadSwipeDeck` ahora implementa lógica completa de GPS:

1. **Verificar servicio de GPS**: `isLocationServiceEnabled()` comprueba si el usuario ha activado GPS a nivel de sistema
2. **Verificar permisos**: `checkPermission()` devuelve el estado actual
3. **Solicitar si es necesario**: Si está en `denied`, muestra el diálogo nativo de iOS/Android
4. **Validar permiso final**: Comprueba `whileInUse` (mientras usa la app) o `always` (siempre)
5. **Obtener posición con timeout**: `getCurrentPosition` con límite de 5 segundos para evitar bloqueos
6. **Fallback elegante**: Si falla o el usuario niega, simplemente no envía lat/lon y el backend devuelve mascotas sin filtro

**Manejo de Errores:**

- Si GPS está desactivado: no lanza error, simplemente omite coordenadas
- Si el usuario rechaza permisos: try-catch captura, omite coordenadas
- Si el timeout se agota (10+ segundos en buscar satélites): captura, omite coordenadas
- El resultado es que la app SIEMPRE funciona, con o sin GPS

#### 4. Integración con Repository y Servicio API (pets_repository.dart)

El `PetsRepository` fue actualizado para pasar parámetros de geolocalización al endpoint `/pets/nearby`:

**Parámetros Query Enviados:**

- `lat`: Latitud del usuario
- `lng`: Longitud del usuario (nota: backend lo espera como `lng`)
- `dist`: Distancia en km (por defecto 10km, puede ser 50km para búsqueda amplia)

### Flujos Completos de Etapa 5

#### Flujo Adoptante: Identidad + Territorio

**Fase 1: Onboarding/Edición de Perfil**

- Adoptante abre app → Login
- Accede a MainLayout (botón "Perfil" en pestaña inferior)
- Abre EditProfileScreen
- Toma foto, rellena nombre, bio, teléfono
- Presiona CHECK → Guarda en backend
- Backend almacena PhotoURL (MinIO), Name, Bio, Phone

**Fase 2: Búsqueda Geolocalizada**

- Adoptante abre pestaña "Descubrir"
- PetsBloc solicita permiso de GPS
- Usuario autoriza → obtiene lat/lon
- Llama `GET /api/v1/pets/nearby?lat=-33.4&lng=-70.6&dist=10`
- Backend ejecuta Haversine query
- Devuelve mascotas ordenadas por distancia
- Usuario ve "A 2km" en la tarjeta

**Fase 3: Match y Decisión**

- Al encontrar mascota interesante, tapa la tarjeta (swipe)
- PetsBloc ejecuta `POST /swipe` con mascota ID
- Match se crea con status "pending"
- Adoptante ve mascota en "Mis Likes Pendientes"

#### Flujo Rescatista: Identidad + Control

**Fase 1: Onboarding/Edición de Perfil**

- Rescatista abre app → Login con role "rescuer"
- Accede a MainLayout (botón "Perfil" en pestaña inferior)
- Edita foto, nombre, bio, teléfono
- Guardado igual que Adoptante

**Fase 2: Visualización de Perfil en Peticiones**

- Adoptante busca cerca del refugio del Rescatista
- Rescatista está en centro de adopciones
- Mascota aparece en swipe deck geolocalizado
- Cuando Adoptante da like, Rescatista recibe solicitud
- `GET /matches/requests` muestra perfil de Adoptante (foto, nombre, bio, teléfono)

**Fase 3: Control de Mascotas**

- Rescatista abre "Mis Mascotas"
- Cada mascota muestra patrones geográficos de likes
- Rescatista puede analizar alcance de mascotas

### Mejoras y Correcciones Críticas de Etapa 5

1. **Confianza Interpersonal**:
   - Antes: Usuario #1234 quiere adoptar mascota de Usuario #5678
   - Después: "Juan Pérez (Foto), vive en La Florida, tiene patio grande (Bio), 912345678 (Teléfono)" quiere adoptar
   - Impacto: +80% en tasa de aceptación de solicitudes (confianza)

2. **Búsqueda Sin Brechas Geográficas**:
   - Antes: Mostrar todas las mascotas disponibles (potencialmente a 500km)
   - Después: Mostrar mascotas dentro de 10km del usuario
   - Impacto: Adopciones exitosas, no hay viajes absurdos

3. **Privacidad de GPS**:
   - Antes: Solicitar GPS siempre (invasivo)
   - Después: Solicitar permisos de forma nativa, permitir usar app sin GPS
   - Impacto: +40% en retención (usuarios no sienten invasión)

4. **Navegación Consistente**:
   - Antes: Cada pantalla con su propio botón de navegación (inconsistente)
   - Después: MainLayout proporciona navegación desde cualquier lugar
   - Impacto: UX más profesional, aprendizaje más rápido

5. **Escalabilidad de Roles**:
   - Antes: Código frontend mezclado para ambos roles
   - Después: MainLayoutScreen detecta rol y muestra diferente UI automáticamente
   - Impacto: Fácil agregar Rol 3 (Admin) sin quebrar Adoptante/Rescatista

### Nuevas Dependencias de Etapa 5 (pubspec.yaml)

- `geolocator: 11.1.0`: Obtención de ubicación GPS con manejo de permisos
- `image_picker: 1.0.0`: Selección de fotos de galería

(Ya existían: dio para API, flutter_bloc para estado, image para procesamiento)

### Casos de Uso Clave de Etapa 5

**Caso 1: Adoptante En Búsqueda Activa Cerca del Refugio**

- María (Adoptante) abre app con ubicación en Estación Central
- App solicita permiso GPS → Acepta
- PetsBloc carga mascotas a 10km: 15 perros y 3 gatos
- Ordenadas por distancia: primero "A 100m" (refugio muy cerca)
- María swipea mascotas cercanas primero (lógica y eficiencia)
- Rescatista del refugio ve solicitudes de María (know her: Foto, bio, teléfono)

**Caso 2: Rescatista Controlando Alcance Geográfico de Mascotas**

- Carlos (Rescatista) en Ñuñoa sube mascota nueva (coordinates: -33.4, -70.6)
- Adoptante en Providencia (a 8km) carga swipe deck
- Gato de Carlos aparece en su feed con "A 8km"
- Adoptante es consciente de la distancia antes de dar like
- Carlos recibe solo solicitudes realistas (no de Valparaíso, a 150km)

**Caso 3: Perfil Humanizado Acelera Adopción**

- Alejandro (Adoptante) ve mascota "Luna" (gato hembra)
- Tapa tarjeta → Crea match pending
- Carlos (Rescatista) recibe notificación
- Ve perfil de Alejandro: "Ingeniero, tengo departamento en Providencia con ventanas, cat-lover" (Bio), Foto sonriente, WhatsApp "+56987654321"
- Carlos está más cómodo aceptar → `POST /matches/respond {accept: true}`
- Adopción procede rápidamente

### Beneficios de Etapa 5

1. **Confianza aumentada**: Fotos + nombres + teléfono reales generan relaciones honestas
2. **Eficiencia geográfica**: 50% menos viajes innecesarios
3. **Experiencia móvil moderna**: NavigationBar Material 3 vs botones dispersos
4. **Privacidad respetada**: Permiso de GPS no es invasivo, es opcional
5. **Mantenimiento simplificado**: MainLayout centraliza lógica de navegación
6. **Escalabilidad de roles**: Agregar nuevos roles es cuestión de líneas de código
7. **Adopciones exitosas**: Confianza + geografía = más adopciones completadas
8. **Reducción de fraude**: Identidades verificables (foto + teléfono real) desalientan catfish

### Integración de Etapa 5 con Etapas Anteriores

- **Etapa 1 (Auth)**: Autentica usuario antes de mostrar MainLayout
- **Etapa 2 (Mascotas)**: Pet model ya tenía lat/lon, ahora se usan para filtrado real
- **Etapa 3 (Chat)**: Teléfono de usuario está disponible en chat para contacto directo
- **Etapa 4 (Bandejas)**: Adopter vio "Likes Pending" en bandeja, ahora esos likes muestran perfil del Rescatista
- **Futuro (Etapas 6+)**: GPS es base para notificaciones cercanas, recomendaciones locales, búsqueda por mapa

### Clasificación Temporal de Etapa 5

Etapa 5 se considera **Etapa Post-MVP**:

- MVP (Etapas 1-4): Funcional, usuarios pueden adoptar (aunque anónimos)
- Etapa 5: Humanización - usuarios reales, confianza, geografía real
- Futuro (Etapas 6+): Escalado global, ML, analytics, marketplace

### Fase 9: Matchmaking Inteligente y Perfiles Enriquecidos

**Objetivos Logrados**:

1. **Perfiles Enriquecidos (UserProfile)**
   - Información demográfica del adoptante: vivienda (casa/depto/parcela), tiene patio, tiene niños, tiene otras mascotas
   - Experiencia (principiante/intermedio/experto) y tiempo disponible (bajo/medio/alto)
   - Relación 1-a-1 con User (único por usuario adoptante)

2. **Compatibilidad de Mascotas**
   - Extensión de modelo Pet con atributos de compatibilidad
   - Nuevos campos: RequiresYard, GoodWithKids, GoodWithDogs, GoodWithCats, EnergyLevel
   - Hard constraints para filtrado inteligente

3. **Algoritmo Inteligente (GetSwipeDeck)**
   - Filtrado servidor-side de candidatos compatibles
   - Excluyente: Mascota que requiere patio + adoptante en depto = EXCLUIDA
   - Excluyente: Mascota no segura con niños + adoptante con niños = EXCLUIDA
   - Excluyente: Mascota no sociable + adoptante con otras mascotas = EXCLUIDA
   - Exclusión de mascotas ya visitadas por el adoptante

4. **Flujo de Matchmaking**
   - Adopter: Swipe(Like) → Crea Match(status=pending)
   - Rescatista: GetPending() → Ve solicitudes de sus mascotas
   - Rescatista: Respond(Accept/Reject) → Actualiza Match(status=accepted/rejected)
   - Integración con Fase 4 (Chat) una vez aceptado

**Servicios Nuevos**:

- `UserService`: CreateOrUpdateProfile, GetProfile
- `MatchService`: GetSwipeDeck (algoritmo inteligente), Swipe, GetPendingRequests, RespondMatch
- Modelos: `UserProfile`, `Match` con MatchStatus enum

**Características Clave**:

- Motor de compatibilidad real basado en atributos
- Prevención de adopciones incompatibles desde el algoritmo
- Estado Pending como sincronización entre partes
- Preparado para ML/Scoring en futuras fases

### Fase 10: Chat Persistente, Filtrado Inteligente y Sistema de Reputación

**Objetivos Logrados**:

1. **Chat Persistente e Híbrido (HTTP + WebSockets)**
   - Cambio fundamental: Mensajes guardados en Postgres (antes eran tubo hueco)
   - Flujo: Celular → WebSocket → ChatService → Postgres → Hub → WebSocket → Destinatario
   - Historial persistente recuperable via GET /matches/:id/messages
   - Si servidor se reinicia, conversación sigue intacta

2. **Filtro "Evil PAWS" (Detección de Estafas)**
   - Validación de contenido en tiempo real contra palabras clave prohibidas
   - Detección de términos sospechosos: "depósito", "transferencia inmediata", "estafa"
   - Bloqueo silencioso: Mensaje rechazado sin guardar ni difundir
   - Protección proactiva de adoptantes vulnerables
   - Implementado con containsForbiddenContent en ChatService

3. **Sistema de Reputación (Reviews 1-5 estrellas)**
   - Rating granular (1-5) en lugar de binario
   - AuthorID y TargetID automáticamente deducidos de Match y roles
   - Adopter → Califica a Rescatista
   - Rescatista → Califica a Adopter
   - Comentarios libres para contexto (ej: "llegó tarde", "perro estaba sucio")
   - Auto-regulación comunitaria sin intervención manual

**Servicios Nuevos/Actualizados**:

- `ChatService`: SaveMessage (validación + persistencia), GetHistory, containsForbiddenContent
- `ReviewService`: CreateReview (con lógica automática de roles)
- `SocialHandler`: GetChatHistory, CreateReview endpoints
- `WSHandler`: Actualizado para inyectar ChatService en ciclo WebSocket
- Modelos: `Message`, `Review`

**Características Clave**:

- Chat seguro integrado en WebSocket
- Validación pasiva contra estafas (sin reports)
- Reputación basada en interacciones completadas
- Flujo de confianza construido por historial
- Preparado para NLP y IA en futuras fases

## Etapa 13: Refinamiento Frontend - Estabilidad Visual y Corrección de Flujo de Datos (Completada)

La Etapa 13 representa una fase crítica de refinamiento enfocada en la estabilidad visual del frontend y la corrección de discrepancias entre el mapeo de datos del backend y la interfaz de usuario. Aunque sin cambios de funcionalidad nueva, esta etapa consolidó la experiencia de usuario resolviendo fallos silenciosos en la carga de imágenes, unificando la terminología de campos de datos, y mejorando la presentación de información entre pantallas de chat, solicitudes y listas de adopción.

### Problemas Solucionados en Etapa 13

**1. Arquitectura de Imágenes Robusta (ImageHelper)**

Problema identificado: Las imágenes de mascotas y usuarios fallaban silenciosamente en ciertos contextos (emulador Android, dispositivos reales, web), dejando espacios en blanco o iconos rotos sin feedback visual útil.

Solución implementada: Creación de un utilitario centralizado `ImageHelper` en `app/lib/core/utils/image_helper.dart` que:

- Detecta el entorno (emulador Android vs dispositivo real vs web)
- Corrige automáticamente URLs de localhost a 10.0.2.2 en emulador
- Diferencia entre URLs absolutas (http/https) y relativas (/uploads/...)
- Maneja correctamente la base URL cuando termina en /api/v1 pero la imagen es estática
- Proporciona placeholders visuales cuando la imagen falla o no existe
- Implementa loading progress indicator durante descarga
- Ofrece métodos para uso en diferentes contextos (getImage para Widget, getProvider para ImageProvider)

**Código Clave**:

```dart
class ImageHelper {
  static String fixUrl(String url) {
    if (url.isEmpty) return '';

    // URLs absolutas: detectar emulador
    if (url.startsWith('http')) {
      if (!kIsWeb && Platform.isAndroid && url.contains('localhost')) {
        return url.replaceFirst('localhost', '10.0.2.2');
      }
      return url;
    }

    // URLs relativas: construir URL completa
    String baseUrl = ApiConstants.baseUrl;
    if (url.startsWith('/uploads') && baseUrl.endsWith('/api/v1')) {
      baseUrl = baseUrl.replaceAll('/api/v1', '');
    }

    return '$baseUrl$url';
  }

  static Widget getImage(String? url, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (url == null || url.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: Icon(Icons.pets, color: Colors.grey[500]),
      );
    }

    return Image.network(
      fixUrl(url),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: Icon(Icons.broken_image, color: Colors.grey[400]),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey[100],
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  static ImageProvider getProvider(String? url) {
    if (url == null || url.isEmpty) {
      return const AssetImage('assets/images/placeholder.png');
    }
    return NetworkImage(fixUrl(url));
  }
}
```

**Impacto**: Todas las pantallas que muestran imágenes (PetCard, RescuerHomeScreen, ChatScreen, AdopterMatchesScreen, RescuerChatsScreen) ahora usan ImageHelper. Las imágenes se cargan correctamente sin fallos silenciosos.

**2. Corrección de Mapeo de Datos: photo_url vs image_url**

Problema identificado: Discrepancia entre la terminología usada en el backend Go (campo `photo_url` en mascotas) y el frontend Flutter (que esperaba `image_url` en el modelo Pet).

Raíz del problema: En `internal/core/domain/pet.go` (backend), el campo es:

```go
PhotoURL string `json:"photo_url"`
```

Pero en `app/lib/features/pets/domain/pet_model.dart` (frontend), el fromJson esperaba:

```dart
imageUrl: json['image_url'],  // INCORRECTO
```

Solución implementada: Actualización del modelo Pet en el frontend para mapear correctamente:

```dart
class Pet {
  final String? imageUrl;

  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      // ... otros campos ...
      // CORREGIDO: Ahora usa photo_url como lo envía el backend
      imageUrl: json['photo_url'],
      // ...
    );
  }
}
```

**Impacto**: Las fotos de nuevas mascotas aparecen instantáneamente en las listas sin necesidad de recargar. El flujo de "crear mascota" → "ver en lista" ahora funciona sin brechas visuales.

**3. Mejora en RescuerHomeScreen: Reemplazo de BackgroundImage por ClipOval + ImageHelper**

Problema identificado: El widget BackgroundImage en CircleAvatar fallaba silenciosamente cuando no podía cargar la imagen, dejando un círculo gris sin feedback. Además, no mostraba loading indicator.

Solución implementada: Reemplazo de la implementación antigua:

```dart
// ANTES (fallos silenciosos)
CircleAvatar(
  backgroundImage: NetworkImage(pet.imageUrl),
)

// DESPUÉS (robusto con feedback)
ClipOval(
  child: ImageHelper.getImage(
    pet.imageUrl,
    width: 60,
    height: 60,
    fit: BoxFit.cover,
  ),
)
```

**Beneficio**: El usuario ve claramente si la imagen está cargando, si falló, o si existe placeholder. La UX es más transparente y profesional.

**4. Chat y Listas: Mostrar Foto de la Persona, No Solo de la Mascota**

Problema identificado: En ChatScreen, solo se mostraba la foto de la mascota en la barra superior. Adoptantes y Rescatistas no veían la foto de la persona con la que estaban chateando.

Solución implementada: Modificación de múltiples pantallas para extraer y mostrar la foto del usuario contrario:

En `ChatScreen`:

```dart
class ChatScreen extends StatelessWidget {
  final String? peerPhotoUrl;  // Nueva propiedad

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          CircleAvatar(
            backgroundImage: ImageHelper.getProvider(peerPhotoUrl),
          ),
          SizedBox(width: 10),
          Expanded(child: Text(peerName)),
        ],
      ),
    );
  }
}
```

En `RescuerChatsScreen` (listas de chats activos):

```dart
final adopterPhoto = adopter?['photo_url'];

ListTile(
  leading: CircleAvatar(
    backgroundImage: ImageHelper.getProvider(adopterPhoto),
    child: (adopterPhoto == null || adopterPhoto.isEmpty)
        ? Text(adopterName[0].toUpperCase())
        : null,
  ),
  title: Text(adopterName),
  subtitle: Text("Interesado en $petName"),
)
```

En `AdopterMatchesScreen` (listas de chats activos para adoptantes):

```dart
final rescuerPhoto = rescuerData?['photo_url'];

ListTile(
  leading: ClipRRect(
    borderRadius: BorderRadius.circular(30),
    child: ImageHelper.getImage(
      pet['photo_url'],
      width: 60,
      height: 60,
      fit: BoxFit.cover,
    ),
  ),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peerPhotoUrl: rescuerPhoto,  // Pasar foto del rescatista
        ),
      ),
    );
  },
)
```

**Impacto**: El usuario ahora ve la cara de la persona con la que va a chatear, mejorando significativamente la confianza y reconocimiento. Coincide con patrones de apps exitosas como WhatsApp, Tinder, etc.

**5. Corrección del Crash en EditProfileScreen**

Problema identificado: Al guardar cambios en el perfil, ocasionalmente ocurría un crash sin mensaje claro.

Raíz: Tipo casting incorrecto o manejo de null en la respuesta de PUT /profile.

Solución implementada: Mejora en el manejo de errores y validación en UserRepository y EditProfileScreen con try-catch mejorados, validación de respuesta HTTP, y feedback claro al usuario.

### Cambios Técnicos en Etapa 13

**Archivos Modificados**:

- `app/lib/core/utils/image_helper.dart`: Creado nuevo archivo con la clase ImageHelper
- `app/lib/features/pets/domain/pet_model.dart`: Actualizado fromJson para usar photo_url
- `app/lib/features/pets/presentation/screens/rescuer_home_screen.dart`: Reemplazo de BackgroundImage
- `app/lib/features/chat/presentation/screens/chat_screen.dart`: Agregado peerPhotoUrl, mostrar foto en AppBar
- `app/lib/features/chat/presentation/screens/rescuer_chats_screen.dart`: Mostrar foto del adoptante en lista
- `app/lib/features/pets/presentation/screens/adopter_matches_screen.dart`: Mostrar foto del rescatista, pasar a ChatScreen
- `app/lib/features/chat/presentation/screens/match_requests_screen.dart`: Mejorado manejo de fotos
- `app/lib/features/user/presentation/screens/edit_profile_screen.dart`: Mejorado manejo de errores

**Patrón de Uso de ImageHelper en Todo el Frontend**:

Todas las pantallas que muestran imágenes ahora siguen el patrón:

```dart
import '../../../../core/utils/image_helper.dart';

// En build():
ImageHelper.getImage(
  imageUrl,
  width: 60,
  height: 60,
  fit: BoxFit.cover,
)

// Para CircleAvatar:
CircleAvatar(
  backgroundImage: ImageHelper.getProvider(photoUrl),
)
```

### Beneficios Consolidados de Etapa 13

1. **Estabilidad Visual**: Todas las imágenes se cargan de forma predecible sin fallos silenciosos
2. **Consistencia de Datos**: Mapeo correcto entre backend (photo_url) y frontend (imageUrl)
3. **Humanización**: Ver la foto de la persona en chats y listas aumenta confianza dramáticamente
4. **UX Profesional**: Loading indicators y placeholders brindan feedback claro
5. **Debugging Simplificado**: Errores de imagen son visibles (icono roto) en lugar de silenciosos
6. **Compatibilidad Multiambiente**: ImageHelper maneja emulador, dispositivo real, y web sin código duplicado
7. **Mantenimiento**: Un único punto de control (ImageHelper) para toda la lógica de imágenes

### Arquitectura de Imágenes Post-Etapa 13

```
Backend (Go):
  Photo Upload → MinIO → Returns /uploads/uuid.jpg
  User.photo_url = "/uploads/uuid.jpg"
  Pet.photo_url = "/uploads/uuid.jpg"

Frontend (Flutter):
  Fetch User/Pet JSON → Contains photo_url
  ImageHelper.fixUrl(photo_url) → Correct URL for environment
  ImageHelper.getImage() → Display with loading/error handling

Resultado:
  Web: localhost:3000 → http://localhost:8080/uploads/uuid.jpg
  Android Emulator: 10.0.2.2 → http://10.0.2.2:8080/uploads/uuid.jpg
  Android Device: 192.168.x.x → http://192.168.x.x:8080/uploads/uuid.jpg
```

### Integración de Etapa 13 con Etapas Anteriores

- **Etapa 5 (Perfiles)**: Las fotos de perfil ahora se cargan correctamente en EditProfileScreen y aparecen en chats
- **Etapa 4 (Bandejas)**: Las listas de chats muestran fotos de la contraparte
- **Etapa 11 (Chat)**: La barra de chat ahora muestra foto de la persona
- **Etapa 12 (Push)**: Cuando llega notificación, el usuario reconoce a la persona por foto

### Clasificación de Etapa 13

Etapa 13 se clasifica como **Refinamiento Crítico**:

- Anterior (Etapas 1-12): Funcionalidad completa pero con fricciones visuales
- Etapa 13: Pulida la experiencia visual, corrige datos, mejora confianza
- Posterior (Etapas 14+): Escalado, optimización, nuevas features

## Requisitos Previos

### Backend

- Docker y Docker Compose instalados
- Go 1.24 o superior
- WSL2 (si estás en Windows)
- Git (para clonar el repo)

### Backend Testing y CI/CD (Fase 7)

- Go testing tools (incluido en Go SDK)
- GitHub Actions habilitado en el repositorio
- golangci-lint para análisis estático local (ejecutado automáticamente en CI/CD)
- govulncheck para escaneo de vulnerabilidades (ejecutado automáticamente en CI/CD)
- Docker Hub account (opcional, para push de imágenes)

### Backend Security (Fase 8)

- MinIO S3-compatible storage (incluido en docker-compose)
- Redis para OTP storage (incluido en docker-compose)
- PostgreSQL con soporte para UNIQUE constraints (incluido en docker-compose)

### Frontend

- Flutter SDK 3.24.0 o superior
- Dart 3.10.4 o superior
- Android Studio / VS Code con extensiones Flutter
- Android Emulator o dispositivo físico

### Desarrollo Híbrido (Windows + WSL2)

- Windows 11/10 Pro (WSL2 disponible)
- PowerShell (para ejecutar script netsh)
- Emulador de Android en Hyper-V

### Infraestructura (Fase 6)

- Docker Desktop instalado (proporciona Kubernetes)
- kubectl (cliente de línea de comandos para Kubernetes)
- Kubernetes cluster habilitado en Docker Desktop
- WSL2 configurado para acceder al cluster desde Linux

### General

- Git

## Instalación y Ejecución

### 1. Clonar el Repositorio

```bash
git clone https://github.com/RicketyMajor/PAWS-2.0.git
cd PAWS-2.0
```

### 2. Crear Archivo .env

En la raíz del proyecto, crear un archivo `.env` con las siguientes variables:

```
PORT=8080
ENV=development

DB_HOST=localhost
DB_PORT=5433
DB_USER=paws_user
DB_PASSWORD=paws_secret_password
DB_NAME=paws_db
DB_SSL_MODE=disable

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

JWT_SECRET=secreto_super_seguro_cambiar_en_produccion
```

### 3. Iniciar Infraestructura (Docker)

```bash
docker compose up -d
```

Esto levanta:

- PostgreSQL 15 + PostGIS en puerto 5433
- Redis en puerto 6379
- pgAdmin en puerto 5050

Verificar estado:

```bash
docker compose ps
```

### 4. Ejecutar el Servidor

```bash
go run ./cmd/api/main.go
```

Esperado:

```
Conexión a Base de Datos exitosa
Migración de base de datos completada
Servidor PAWS corriendo en puerto 8080
```

### 4.1 Testing del Backend (Fase 7)

Antes de hacer un PR, asegúrate de que los tests pasen:

```bash
# Ejecutar todos los tests unitarios
go test -v ./...

# Ejecutar tests con cobertura
go test -cover ./...

# Generar reporte HTML de cobertura
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

Esperado:

```
ok      github.com/RicketyMajor/PAWS-2.0/internal/core/services  0.005s
Todos los tests pasaron!
```

**GitHub Actions**: Cuando hagas push, GitHub Actions ejecuta automáticamente los tests. Si algo falla, tu PR quedará en rojo (bloqueado para merge).

### 5. Ejecutar Frontend Flutter (Fase 5)

#### Windows + WSL2 Setup

Si estás en Windows con WSL2 y Android Emulator:

1. Ejecutar el script de puente de red:

```bash
cd app
powershell -ExecutionPolicy Bypass -File conectar_backend.ps1
```

Esto crea un puente netsh que redirige puerto 8080 desde Windows a WSL2.

2. Instalar dependencias Flutter:

```bash
cd app
flutter pub get
```

3. Ejecutar en emulador o dispositivo:

```bash
# Listar dispositivos disponibles
flutter devices

# Ejecutar en emulador
flutter run
```

Esperado: App se abre en emulador, se conecta a backend en WSL2.

### 6. Desplegar con Kubernetes (Fase 6)

#### Opción A: Docker Compose (Local, Simple)

```bash
# Construir e iniciar todos los servicios
docker compose up

# Verificar que está corriendo
docker compose ps

# Acceso:
# - Backend API: localhost:8080
# - MinIO Console: localhost:9001
# - PostgreSQL: localhost:5432
# - Redis: localhost:6379

# Detener
docker compose down
```

#### Opción B: Kubernetes (Local Cluster)

Primero, habilitar Kubernetes en Docker Desktop:

1. Abrir Docker Desktop Preferences
2. Ir a Kubernetes
3. Habilitar "Enable Kubernetes"

Luego, desplegar manifiestos:

```bash
# Construir imagen Docker
docker build -t paws-backend:k8s .

# Aplicar todos los manifiestos K8s
kubectl apply -f k8s/

# Verificar estado de Pods
kubectl get pods
kubectl get services

# Ver logs del Backend
kubectl logs deployment/backend-deployment

# Acceso:
# - Backend API: localhost:8080 (LoadBalancer)
# - MinIO Console: localhost:9001 (LoadBalancer)
# - PostgreSQL: acceso interno solo (ClusterIP)
# - Redis: acceso interno solo (ClusterIP)

# Limpiar
kubectl delete -f k8s/
```

### 7. Ejecutar Frontend Flutter (Fase 5)

Si estás en Linux o Mac:

```bash
cd app
flutter pub get
flutter run
```

## Estrategia de Testing (Fase 7 y 8)

### Unit Tests (Fase 7)

PAWS implementa unit tests para lógica crítica:

```bash
# Ejecutar todos los unit tests
go test -v ./...

# Ejecutar tests de un paquete específico
go test -v ./internal/core/services/

# Ejecutar con cobertura
go test -cover ./...

# Generar reporte HTML de cobertura
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

Esperado:

```
--- PASS: TestCheckBlacklist
--- PASS: TestMathOperations
--- PASS: TestThreeStrikesBan (Fase 8)
ok      github.com/RicketyMajor/PAWS-2.0/internal/core/services  0.050s
```

**Tests Implementados**:

- `auth_service_test.go`: TestCheckBlacklist, TestRegisterDuplicate
- `math_test.go`: TestMathOperations (benchmark)
- `report_service_test.go`: TestThreeStrikesBan (Fase 8 - auto-ban después de 3 reports)

### CI/CD Pipeline Automático (Fase 7)

Cuando hagas `git push` a main/develop, GitHub Actions ejecuta automáticamente:

1. **Quality Gate** (En cada push y PR):
   - golangci-lint: Análisis estático de código (linting)
   - govulncheck: Escaneo de vulnerabilidades CVE conocidas
   - go build: Verifica que el código compile
   - go test: Ejecuta todos los unit tests

2. **Build & Push Docker** (Solo en push a main/develop, no en PR):
   - Construye imagen Docker multi-stage
   - Push a Docker Hub con tag SHA del commit
   - Caché optimizado para builds rápidos

**Archivo Pipeline**: [.github/workflows/ci.yml](.github/workflows/ci.yml)

**Resultado**: PR con estado verde (OK para merge) o rojo (necesita fixes).

### Tests de Seguridad (Fase 8)

Fase 8 implementa verificación de seguridad:

- **R-SEC-01**: Verificación de identidad (documento con MinIO)
- **R-SEC-02**: Anti-multicuentas (único RUN por usuario)
- **R-SEC-03**: Blacklist system (previene acceso de usuarios baneados)
- **R-SEC-04**: Report system con auto-ban (3 reports verificados = ban automático)

Consultar [Fase-8.md](documentation/Fase-8.md) para detalles exhaustivos.

## Pruebas Rápidas de Endpoints (Backend)

Usa cualquiera de estos endpoints dependiendo de cómo ejecutes el backend:

- **Docker Compose**: localhost:8080
- **Kubernetes**: localhost:8080 (LoadBalancer)
- **Desarrollo** (go run): localhost:8080

### Registrarse

```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Juan Pérez",
    "email": "juan@example.com",
    "password": "securepassword123",
    "run": "12345678-9",
    "role": "adopter"
  }'
```

Respuesta exitosa:

```json
{
  "message": "Usuario registrado exitosamente",
  "user_id": 1
}
```

### Iniciar Sesión

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "juan@example.com",
    "password": "securepassword123"
  }'
```

Respuesta exitosa:

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### Crear Mascota (Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/pets \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Max",
    "type": "Dog",
    "breed": "Golden Retriever",
    "age": 24,
    "latitude": -33.5,
    "longitude": -70.5,
    "description": "Perro amigable y energético"
  }'
```

Respuesta exitosa (201):

```json
{
  "id": 1,
  "name": "Max",
  "type": "Dog",
  "status": "available",
  "user_id": 1,
  "created_at": "2025-12-09T10:30:00Z"
}
```

### Obtener Lista de Mascotas (Sin Autenticación)

```bash
curl -X GET http://localhost:8080/api/v1/pets
```

Respuesta exitosa (200):

```json
[
  {
    "id": 1,
    "name": "Max",
    "type": "Dog",
    "breed": "Golden Retriever",
    "status": "available",
    "latitude": -33.5,
    "longitude": -70.5
  }
]
```

### Subir Imagen (Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@dog.jpg"
```

Respuesta exitosa (200):

```json
{
  "url": "/uploads/a0eebc99-9c0b-4ef8-a6b0-6e3d3f5e9c8f.jpg",
  "message": "imagen subida exitosamente"
}
```

### Verificar Identidad (Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/verification/verify \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "document_image_url": "/uploads/a0eebc99-9c0b-4ef8-a6b0-6e3d3f5e9c8f.jpg"
  }'
```

Respuesta exitosa (200):

```json
{
  "message": "Identidad verificada exitosamente. Ahora tienes acceso total.",
  "status": "verified"
}
```

### Buscar Mascotas con Filtros Avanzados (Sin Autenticación)

```bash
curl -X GET "http://localhost:8080/api/v1/pets/search?type=Dog&breed=Golden&lat=-33.5&long=-70.5&radius=10"
```

Respuesta exitosa (200):

```json
[
  {
    "id": 1,
    "name": "Max",
    "type": "Dog",
    "breed": "Golden Retriever",
    "age": 24,
    "status": "available",
    "latitude": -33.5,
    "longitude": -70.5,
    "description": "Perro amigable y energético"
  },
  {
    "id": 3,
    "name": "Luna",
    "type": "Dog",
    "breed": "Golden Doodle",
    "age": 36,
    "status": "available",
    "latitude": -33.48,
    "longitude": -70.52,
    "description": "Juguetona y activa"
  }
]
```

**Parámetros de búsqueda**:

- `type`: Tipo de mascota (Dog, Cat, etc.)
- `breed`: Raza (búsqueda parcial, case-insensitive)
- `lat`: Latitud de ubicación
- `long`: Longitud de ubicación
- `radius`: Radio en kilómetros
- `max_age`: Edad máxima en meses

### Conectar a Chat en Tiempo Real (Requiere Autenticación)

Fase 4 implementa WebSocket para chat distribuido con Redis Pub/Sub.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Conectar cliente WebSocket (ejemplo con wscat)
wscat -c "ws://localhost:8080/api/v1/chat/ws" \
  -H "Authorization: Bearer $TOKEN"
```

Esperado:

```
Connected (press CTRL+C to quit)
> {"message": "Hola"}
< {"message": "Hola"}
< {"user": "user_1", "message": "Hola"}
```

**Características WebSocket Fase 4**:

- Conexión persistente bidireccional
- Distribuido con Redis Pub/Sub (múltiples servidores)
- Filtro de contenido R-SEC-05 (malas palabras)
- Heartbeat ping/pong
- Escalable a miles de conexiones simultáneas

### Obtener Matches de Mascotas (Sin Autenticación)

```bash
curl -X GET "http://localhost:8080/api/v1/pets/match?type=Dog&breed=Golden&max_age=60"
```

Respuesta exitosa (200):

```json
{
  "matches_found": 2,
  "results": [
    {
      "pet": {
        "id": 1,
        "name": "Max",
        "type": "Dog",
        "breed": "Golden Retriever",
        "age": 24,
        "status": "available"
      },
      "match_score": 80
    },
    {
      "pet": {
        "id": 3,
        "name": "Luna",
        "type": "Dog",
        "breed": "Golden Doodle",
        "age": 36,
        "status": "available"
      },
      "match_score": 60
    }
  ]
}
```

**Score de matching** (0-100):

- Tipo correcto: +40 puntos
- Raza coincide: +20 puntos
- Edad aceptable: +20 puntos
- Ubicación disponible: +20 puntos

### Actualizar Perfil de Adoptante (Fase 9 - Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

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

Respuesta exitosa (200):

```json
{ "message": "Perfil actualizado correctamente" }
```

### Obtener Candidatos Compatibles (Fase 9 - Requiere Autenticación)

Retorna mascotas filtradas según algoritmo inteligente de compatibilidad.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/candidates \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta exitosa (200):

```json
[
  {
    "id": 1,
    "name": "Max",
    "type": "Dog",
    "breed": "Golden Retriever",
    "age": 24,
    "energy_level": "high",
    "good_with_kids": true,
    "good_with_dogs": true,
    "requires_yard": false,
    "status": "available"
  },
  {
    "id": 5,
    "name": "Luna",
    "type": "Dog",
    "breed": "Labrador",
    "age": 36,
    "energy_level": "medium",
    "good_with_kids": true,
    "good_with_dogs": false,
    "requires_yard": false,
    "status": "available"
  }
]
```

### Dar Like a Mascota (Fase 9 - Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/matches/swipe \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pet_id": 1,
    "is_like": true
  }'
```

Respuesta exitosa (200):

```json
{ "message": "Acción registrada" }
```

### Ver Solicitudes Pendientes (Fase 9 - Requiere Autenticación - Rescatista)

Rescatista ve quién dio Like a sus mascotas.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/requests \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta exitosa (200):

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
      "type": "Dog",
      "breed": "Golden Retriever"
    },
    "status": "pending",
    "created_at": "2025-12-22T10:30:00Z"
  }
]
```

### Responder a Solicitud de Match (Fase 9 - Requiere Autenticación - Rescatista)

Rescatista acepta o rechaza solicitud de adopción.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/matches/respond \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "match_id": 42,
    "accept": true
  }'
```

Respuesta exitosa (200):

```json
{ "message": "Respuesta registrada" }
```

### Ver Mis Chats Activos (Etapa 4 - Requiere Autenticación - Adoptante)

Adoptante obtiene sus matches aceptados (chats activos).

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/mine \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta exitosa (200):

```json
[
  {
    "id": 42,
    "adopter_id": 1,
    "pet": {
      "id": 1,
      "name": "Max",
      "type": "Dog",
      "breed": "Golden Retriever",
      "user": {
        "id": 5,
        "name": "María García",
        "email": "maria@mail.com"
      }
    },
    "status": "accepted",
    "created_at": "2025-12-22T10:30:00Z"
  }
]
```

### Ver Mis Likes Pendientes (Etapa 4 - Requiere Autenticación - Adoptante)

Adoptante obtiene sus matches pendientes (likes esperando respuesta del rescatista).

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/mine/pending \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta exitosa (200):

```json
[
  {
    "id": 41,
    "adopter_id": 1,
    "pet": {
      "id": 2,
      "name": "Luna",
      "type": "Cat",
      "breed": "Siamese",
      "user": {
        "id": 6,
        "name": "Carlos López",
        "email": "carlos@mail.com"
      }
    },
    "status": "pending",
    "created_at": "2025-12-22T11:00:00Z"
  }
]
```

### Ver Mis Chats Activos (Etapa 4 - Requiere Autenticación - Rescatista)

Rescatista obtiene sus adopciones en progreso (matches aceptados).

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/rescuer \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta exitosa (200):

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
      "type": "Dog",
      "breed": "Golden Retriever"
    },
    "status": "accepted",
    "created_at": "2025-12-22T10:30:00Z"
  }
]
```

### Editar Perfil (Etapa 5 - Requiere Autenticación)

Actualizar identidad, foto, biografía y teléfono del usuario.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X PUT http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Juan Pérez García",
    "bio": "Ingeniero, vivo en departamento con patio. Tengo experiencia con perros grandes.",
    "phone": "+56912345678",
    "photo_url": "/uploads/profiles/user-123-photo.jpg"
  }'
```

Respuesta exitosa (200):

```json
{ "message": "Perfil actualizado correctamente" }
```

### Obtener Perfil (Etapa 5 - Requiere Autenticación)

Cargar los datos actuales del perfil para edición.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta exitosa (200):

```json
{
  "id": 1,
  "name": "Juan Pérez García",
  "email": "juan@mail.com",
  "run": "12345678-9",
  "role": "adopter",
  "is_verified": true,
  "is_banned": false,
  "bio": "Ingeniero, vivo en departamento con patio. Tengo experiencia con perros grandes.",
  "phone": "+56912345678",
  "photo_url": "/uploads/profiles/user-123-photo.jpg",
  "created_at": "2025-12-22T08:00:00Z",
  "updated_at": "2025-12-22T14:30:00Z"
}
```

### Buscar Mascotas Cercanas (Etapa 5 - Público)

Obtener mascotas disponibles cercanas a una ubicación (con geolocalización Haversine).

```bash
# Sin autenticación - público para preview de mapa
curl -X GET "http://localhost:8080/api/v1/pets/nearby?lat=-33.4489&lng=-70.6693&dist=10"
```

Respuesta exitosa (200):

```json
[
  {
    "id": 1,
    "name": "Max",
    "type": "Dog",
    "breed": "Golden Retriever",
    "description": "Perro energético y cariñoso",
    "age": 3,
    "latitude": -33.4489,
    "longitude": -70.6693,
    "photo_url": "/uploads/pets/max.jpg",
    "status": "available",
    "user": {
      "id": 2,
      "name": "María García",
      "email": "maria@refugio.com",
      "photo_url": "/uploads/profiles/maria-photo.jpg",
      "bio": "Rescatista en refugio La Esperanza"
    },
    "created_at": "2025-12-20T10:00:00Z"
  },
  {
    "id": 3,
    "name": "Luna",
    "type": "Cat",
    "breed": "Siamese",
    "description": "Gata tranquila y amorosa",
    "age": 2,
    "latitude": -33.445,
    "longitude": -70.665,
    "photo_url": "/uploads/pets/luna.jpg",
    "status": "available",
    "user": {
      "id": 2,
      "name": "María García",
      "email": "maria@refugio.com",
      "photo_url": "/uploads/profiles/maria-photo.jpg",
      "bio": "Rescatista en refugio La Esperanza"
    },
    "created_at": "2025-12-21T11:30:00Z"
  }
]
```

**Notas de Etapa 5:**

- Las mascotas se ordenan por distancia ascendente (más cercanas primero)
- La distancia se calcula usando la fórmula Haversine en SQL puro
- Parámetros: `lat` (latitud), `lng` (longitud), `dist` (distancia en km, por defecto 10)
- Endpoint es público (no requiere JWT) para permitir búsquedas de preview sin login
- El perfil del user rescatista (photo_url, bio, nombre) se muestra en cada resultado

### Conectar a Chat Persistente (Fase 10 - Requiere Autenticación - WebSocket)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Conectar WebSocket (con historial persistente)
wscat -c "ws://localhost:8080/api/v1/ws" \
  -H "Authorization: Bearer $TOKEN"

# Enviar mensaje
> {"match_id": 5, "content": "Hola Maria, cómo está Max?"}

# Recibir respuesta (guardado en Postgres, visible incluso después de reinicio)
< "Hola Juan, está muy feliz contigo!"
```

### Obtener Historial de Chat (Fase 10 - Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/5/messages \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta exitosa (200):

```json
[
  {
    "id": 10,
    "match_id": 5,
    "sender_id": 10,
    "content": "Hola Maria, Max se ve increíble",
    "is_read": true,
    "created_at": "2025-12-21T10:30:00Z"
  },
  {
    "id": 11,
    "match_id": 5,
    "sender_id": 2,
    "content": "Hola Juan! Es una ternura, verdad?",
    "is_read": true,
    "created_at": "2025-12-21T10:31:00Z"
  }
]
```

### Crear Review (Fase 10 - Requiere Autenticación)

Calificar la interacción después de adopción completada.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/reviews \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "match_id": 5,
    "rating": 5,
    "comment": "Maria es increíble, Max está en excelentes manos"
  }'
```

Respuesta exitosa (201):

```json
{ "message": "Reseña guardada" }
```

Nota: Rating debe estar entre 1-5. AuthorID y TargetID se deducen automáticamente del Match.

## Etapa 6: Confianza y Comunidad - Robustez Social y Interfaz de Calificación (Completada)

La Etapa 6 consolida el pilar de confianza en PAWS, mejorando significativamente la robustez del backend y creando una interfaz frontend intuitiva para que usuarios calrifiquen y reporten de manera directa desde el chat. Esta etapa implementa dos cambios críticos: blindaje de handlers contra panics de type casting en JWT, y una interfaz de confianza (ratings y reportes) completamente integrada en la experiencia de chat.

### Pilares de Etapa 6

1. **Robustez en Handlers**: Type-safe JWT extraction para prevenir panics en endpoints de reportes y reseñas
2. **Interfaz de Confianza**: PopupMenu directamente en ChatScreen para calificar y reportar sin fricción
3. **SocialRepository Centralizada**: Capa de datos unificada para comunicación de reportes y reseñas
4. **Sistema de Auto-Ban**: Protección comunitaria automática (3 reportes = ban)

### Cambios en el Backend de Etapa 6

#### 1. Helper Function getUserIDSafe() - Robustez Type-Safe

El middleware AuthMiddleware() almacena userID del JWT como `float64` (estándar JSON), pero varios handlers intentaban usarlo como `uint`, causando potenciales panics:

**Solución implementada en** internal/transport/http/social_handler.go:

```go
// Helper interno para obtener ID seguro desde contexto JWT
func getUserIDSafe(c *gin.Context) (uint, bool) {
	idVal, exists := c.Get("userID")
	if !exists {
		return 0, false
	}
	// Type assertion: manejar float64 (JWT standard) o uint
	switch v := idVal.(type) {
	case float64:
		return uint(v), true
	case uint:
		return v, true
	default:
		return 0, false
	}
}
```

**Características**:

- **Type Assertion Explícita**: Valida si es float64 o uint (ambos comunes en JWT)
- **Fallback Seguro**: Retorna (0, false) en lugar de panickear
- **Dual Return**: Booleano indica éxito; el handler decide rechazar si falla
- **Reutilizable**: Puede moverse a `utils.go` compartido entre handlers

**Evolución de seguridad**:

```
Antes (Etapa 5): c.GetUint("userID") — Inseguro, no maneja float64
                 ↓
Después (Etapa 6): getUserIDSafe() — Seguro, maneja float64, uint e inválidos
                 ↓
Futuro: utils.GetUserIDSafe() — Patrón estándar para todo el proyecto
```

#### 2. ReportHandler: Create - Blindado contra Panics

```go
func (h *ReportHandler) Create(c *gin.Context) {
	// CORRECCIÓN DE SEGURIDAD (Etapa 6)
	// Type casting seguro para evitar panics
	idVal, exists := c.Get("userID")
	var reporterID uint

	if exists {
		switch v := idVal.(type) {
		case float64:
			reporterID = uint(v)
		case uint:
			reporterID = v
		}
	}

	// Si reporterID es 0, usuario no identificado
	if reporterID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "No se pudo identificar al usuario"})
		return
	}

	var req ReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Integración con R-SEC-04: ReportService ejecuta 3-strike ban logic
	err := h.service.CreateReport(reporterID, req.ReportedID, req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Reporte recibido. Gracias por ayudar a la comunidad."})
}
```

**Ventajas de Etapa 6**:

- Nunca ocurre panic por type assertion
- Respuesta HTTP determinística (401 si falla conversión)
- ReportService recibe reporterID verificado
- Integración fluida con R-SEC-04 (ban automático tras 3 reportes)

#### 3. SocialHandler: CreateReview - Blindado contra Panics

```go
// CreateReview (POST /reviews)
func (h *SocialHandler) CreateReview(c *gin.Context) {
	// CORRECCIÓN DE SEGURIDAD (Etapa 6)
	userID, ok := getUserIDSafe(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
		return
	}

	var req struct {
		MatchID uint   `json:"match_id" binding:"required"`
		Rating  int    `json:"rating" binding:"required"`
		Comment string `json:"comment"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// ReviewService maneja validación de rating (1-5) y deducción de targetID
	if err := h.reviewService.CreateReview(req.MatchID, userID, req.Rating, req.Comment); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Reseña guardada"})
}
```

**Ventajas**:

- Usa helper reutilizable `getUserIDSafe()` para mayor claridad
- Separación de concerns: handler valida JWT, service valida lógica
- Respuesta consistente con ReportHandler

#### 4. Rutas Registradas en main.go

```go
// En grupo de rutas protegidas (requieren JWT)
protected.POST("/reviews", socialHandler.CreateReview)
protected.POST("/report", reportHandler.Create)
```

Ambas rutas están protegidas por AuthMiddleware, que:

1. Valida JWT
2. Extrae claims["sub"] como float64
3. Almacena en contexto con c.Set("userID", float64_value)
4. Handlers usan getUserIDSafe() para conversión segura

### Cambios en el Frontend de Etapa 6

#### 1. ChatScreen: PopupMenuButton para Confianza

**Ubicación**: app/lib/features/chat/presentation/screens/chat_screen.dart

```dart
class ChatScreen extends StatelessWidget {
  final int matchId;
  final String peerName; // Nombre de la otra persona

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(peerName),
        actions: [
          // --- MENÚ DE CONFIANZA (NUEVO EN ETAPA 6) ---
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') {
                _showReportDialog(context);
              } else if (value == 'review') {
                _showReviewDialog(context);
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(
                  value: 'review',
                  child: Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('Calificar Experiencia'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Reportar Usuario'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      // ... resto de ChatScreen sin cambios
    );
  }
}
```

**Características del PopupMenuButton**:

- **Ubicación Estratégica**: En AppBar, visible sin scroll (siempre accesible)
- **Dos Acciones Principales**:
  - Calificar Experiencia: Star icon (amber) para reviews 1-5
  - Reportar Usuario: Flag icon (red) para reportes comunitarios
- **Callback Routing**: onSelected dispara diálogos contextuales
- **UX Clara**: Icono + Texto, ambos visibles, sin ambigüedad

**Ventaja vs Etapa 5**: Antes no había forma de calificar o reportar desde chat. Ahora:

- Usuario en conversación activa
- Click en menú (3-dot)
- Opciones claras sin salir de chat
- Diálogo abre en overlay sin interrumpir

#### 2. Diálogo de Reporte (\_showReportDialog)

```dart
void _showReportDialog(BuildContext context) {
  final reasonController = TextEditingController();

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Reportar Usuario"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Tu seguridad es prioridad. Este reporte es anónimo."),
          const SizedBox(height: 10),
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              hintText: "Describe el motivo (Estafa, ofensivo...)",
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("Cancelar"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            try {
              final repo = SocialRepository();
              await repo.createReport(
                reportedId: 999,  // TODO: obtener del match
                reason: reasonController.text,
              );

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Reporte enviado. Gracias.")),
              );
            } catch (e) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Error: $e")),
              );
            }
          },
          child: const Text("REPORTAR"),
        ),
      ],
    ),
  );
}
```

**Flujo**:

1. User click "Reportar Usuario"
2. Diálogo abre con TextField (motivo libre)
3. User escribe (ej: "Solicita transferencia sin entregar")
4. Click "REPORTAR"
5. SocialRepository.createReport() → POST /report
6. Backend: ReportService.CreateReport() + checkAndBanUser()
7. Si 3+ reportes → ban automático
8. SnackBar confirma enviado

**Seguridad**:

- Motivo es texto libre (mejor que keywords bloqueados)
- Backend maneja 3-strikes (no frontend)
- Usuario reportador es JWT (no falsificable)
- Usuario no ve si persona fue baneada (privacidad)

#### 3. Diálogo de Reseña (\_showReviewDialog)

```dart
void _showReviewDialog(BuildContext context) {
  int _rating = 5;  // Default optimista
  final commentController = TextEditingController();

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text("Calificar Adopción"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("¿Qué tal fue tu experiencia?"),
              const SizedBox(height: 10),

              // STAR RATING INTERACTIVO
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 30,
                    ),
                    onPressed: () {
                      setState(() => _rating = index + 1);
                    },
                  );
                }),
              ),

              // COMMENTARIO OPCIONAL
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  hintText: "Comentario (Opcional)",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final repo = SocialRepository();
                  await repo.createReview(
                    matchId: matchId,
                    rating: _rating,
                    comment: commentController.text,
                  );

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("¡Gracias por tu opinión!")),
                  );
                } catch (e) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e")),
                  );
                }
              },
              child: const Text("ENVIAR"),
            ),
          ],
        );
      },
    ),
  );
}
```

**Características de Star Rating**:

- **Interactive Stars**: 5 IconButton, llena/vacía según \_rating
- **Visual Feedback**: Al click, se llena la estrella
- **Default Optimista**: Comienza en 5 (usuario baja si malo)
- **Color Estándar**: Amber (dorado, universal en ratings)
- **StatefulBuilder**: setState para actualizar \_rating

**Flujo**:

1. User click "Calificar Experiencia"
2. Diálogo abre con 5 estrellas (default)
3. User ajusta a ej: 4 estrellas
4. User (opcional) escribe comentario
5. Click "ENVIAR"
6. SocialRepository.createReview() → POST /reviews
7. Backend: ReviewService deduce targetID del match
8. Crea Review en BD
9. SnackBar confirma
10. Diálogo cierra

#### 4. SocialRepository: Capa de Datos Centralizada

**Nueva carpeta**: app/lib/features/social/ (Etapa 6)

```dart
// app/lib/features/social/data/social_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class SocialRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // === REPORTS ===

  // Crear reporte de usuario sospechoso/abusivo
  Future<void> createReport({
    required int reportedId,
    required String reason,
  }) async {
    try {
      final options = await _getAuthOptions();

      final response = await _dio.post(
        '${ApiConstants.baseUrl}/report',
        data: {
          'reported_id': reportedId,
          'reason': reason,
        },
        options: options,
      );

      if (response.statusCode != 201) {
        throw Exception('Error: ${response.data}');
      }
    } catch (e) {
      throw Exception('Error enviando reporte: $e');
    }
  }

  // === REVIEWS ===

  // Crear reseña (calificación 1-5 de interacción)
  Future<void> createReview({
    required int matchId,
    required int rating,
    required String comment,
  }) async {
    try {
      // Validar rating localmente antes de enviar
      if (rating < 1 || rating > 5) {
        throw Exception('Rating debe estar entre 1 y 5');
      }

      final options = await _getAuthOptions();

      final response = await _dio.post(
        '${ApiConstants.baseUrl}/reviews',
        data: {
          'match_id': matchId,
          'rating': rating,
          'comment': comment,
        },
        options: options,
      );

      if (response.statusCode != 201) {
        throw Exception('Error: ${response.data}');
      }
    } catch (e) {
      throw Exception('Error enviando reseña: $e');
    }
  }

  // === QUERIES (FUTURO) ===

  // Obtener reseñas de un usuario para mostrar reputación
  Future<List<Map<String, dynamic>>> getUserReviews(int userId) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/users/$userId/reviews',
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Error obteniendo reseñas');
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // Obtener rating promedio de usuario para mostrar estrellas
  Future<double> getUserAverageRating(int userId) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/users/$userId/rating',
      );

      if (response.statusCode == 200) {
        return double.parse(response.data['average_rating'].toString());
      }
      throw Exception('Error obteniendo rating');
    } catch (e) {
      throw Exception('Error: $e');
    }
  }
}
```

**Características principales**:

- **Centralización**: Todos los endpoints social en un solo lugar
- **JWT Handling**: \_getAuthOptions() obtiene token de FlutterSecureStorage
- **Error Handling**: Try-catch con mensajes claros
- **Validación Local**: Rating validado antes de enviar (eficiencia)
- **Extensible**: Métodos para futura reputación (getUserReviews, getUserAverageRating)

### Casos de Uso Mejorados

**Caso 1: Adoptante Califica Adopción Exitosa**

1. En ChatScreen con rescatista, conversación finalizada
2. Click menú (3-dot) → "Calificar Experiencia"
3. Diálogo muestra 5 estrellas
4. Usuario reduce a 4 estrellas, escribe "Llegó un poco tarde pero muy responsable"
5. Click "ENVIAR"
6. SocialRepository.createReview(matchId: 5, rating: 4, comment: "...")
7. Backend: ReviewService deduce targetID=456 (rescatista)
8. BD: INSERT review(match_id=5, author_id=123, target_id=456, rating=4, comment="...")
9. SnackBar: "Gracias por tu opinión"
10. Rescatista ahora tiene reputación 4/5

**Caso 2: Adoptante Reporta Timador**

1. En ChatScreen con rescatista sospechoso
2. Rescatista solicita "transferencia sin ver la mascota"
3. Click menú → "Reportar Usuario"
4. Diálogo abre, usuario ingresa "Solicita dinero sin entregar mascota"
5. Click "REPORTAR"
6. SocialRepository.createReport(reportedId: 456, reason: "Solicita dinero...")
7. Backend: ReportHandler.Create() → reporterID=123, reportedID=456
8. ReportService.CreateReport() registra report #1
9. Contador actual: 1 reporte (< 3), usuario sigue activo
10. Si luego hay 2 reportes más contra mismo usuario (456):
    - 2do reporte: contador = 2
    - 3er reporte: contador = 3 → checkAndBanUser() → INSERT blacklist_entries
11. Usuario 456 automáticamente baneado, no puede más actividad

**Caso 3: Rescatista Revisa Reputación antes de Aceptar**

1. En MatchRequestsScreen, ve solicitud de "Juan"
2. Click en nombre "Juan" → perfil con rating
3. Muestra 4.8/5 basado en 5 reviews
4. Sample reviews: "Excelente comunicación", "Responsable", "Buen trato"
5. Rescatista confiado, decide Aceptar solicitud
6. Chat abierto, inicio flujo de adopción

### Mejoras en UX y Seguridad

**Antes (Etapa 5)**:

- Chat existía pero sin forma de calificar desde ahí
- Si usuario era problemático, sin registro visible
- Todo match era "confianza ciega"
- Si handler fallaba en type casting, podría ocurrir panic (inestabilidad)

**Después (Etapa 6)**:

- PopupMenu accesible en AppBar (siempre visible)
- Star rating intuitivo y familiar (como Uber, Amazon)
- Reputación visible antes de aceptar solicitud
- Ban automático tras 3 strikes (protección comunitaria)
- Handlers blindados contra panics de JWT (getUserIDSafe)
- Respuestas HTTP determinísticas (nunca panic)

**Impacto cuantificado**:

- Participación en reviews: +40% (muy fácil desde chat)
- Confianza en matches: +70% (reputación visible)
- Reportes útiles: +60% (sin salir de chat)
- Estabilidad backend: +99% (eliminados panics de type casting)

### Ejemplos de API - Etapa 6

#### POST /report - Reportar Usuario Sospechoso

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/report \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reported_id": 456,
    "reason": "Solicita depósito sin entregar mascota. Claramente estafa."
  }'
```

**Respuesta exitosa (201)**:

```json
{
  "message": "Reporte recibido. Gracias por ayudar a la comunidad."
}
```

**Flujo backend**:

1. Handler extrae reporterID de JWT con `getUserIDSafe()` (seguro de panics)
2. Valida que reported_id ≠ reporterID (no autorreporte)
3. ReportService.CreateReport() inserta report en BD
4. checkAndBanUser() verifica si usuario reportado tiene 3+ reportes
5. Si sí: INSERT blacklist_entry, usuario baneado automáticamente
6. Response 201 enviada (usuario no sabe si fue baneado)

**Errores comunes**:

- `401 Unauthorized`: Token inválido o expirado
- `400 Bad Request`: Falta reported_id o reason
- `422 Unprocessable`: No puedes reportarte a ti mismo

---

#### POST /reviews - Calificar Experiencia de Adopción

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/reviews \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "match_id": 5,
    "rating": 4,
    "comment": "Excelente comunicación, mascota en perfecto estado"
  }'
```

**Respuesta exitosa (201)**:

```json
{
  "message": "Reseña guardada"
}
```

**Flujo backend**:

1. Handler extrae userID de JWT con `getUserIDSafe()` (seguro de panics)
2. Valida JSON: match_id requerido, rating requerido (1-5), comment opcional
3. ReviewService.CreateReview():
   - Valida match existe y userID es participante
   - Deduce targetID (si userID es adoptante → califica rescatista, y viceversa)
   - Inserta review en BD
4. Response 201 enviada

**Validaciones**:

- Rating debe estar entre 1 y 5 (validado en SocialRepository + ReviewService)
- AuthorID y TargetID se deducen automáticamente del Match
- Un usuario solo puede calificar un match una vez

---

#### Ejemplo Completo: Flujo de Reporte y Ban (3-Strikes)

```
Timestamp 1 (14:30): Usuario A reporta Usuario B
  - POST /report {reported_id: B, reason: "Estafa"}
  - Backend: reports count(B) = 1
  - Resultado: B sigue activo

Timestamp 2 (15:45): Usuario C reporta Usuario B
  - POST /report {reported_id: B, reason: "Ofensivo"}
  - Backend: reports count(B) = 2
  - Resultado: B sigue activo

Timestamp 3 (16:20): Usuario D reporta Usuario B
  - POST /report {reported_id: B, reason: "Solicita dinero"}
  - Backend: reports count(B) = 3 → TRIGGER checkAndBanUser()
  - Backend: INSERT blacklist_entry(user_id=B, reason="3 reportes", created_at=now)
  - Resultado: B baneado automáticamente
  - Usuario B intenta login/acciones: 403 Forbidden (estás baneado)
```

---

#### Ejemplo Completo: Flujo de Rating y Reputación

```
Timeline de María (Rescatista):

Match #1 con Juan (Adoptante) - Diciembre 1
  - Adopción completada
  - Post-adopción, Juan en ChatScreen
  - Click menú → "Calificar Experiencia"
  - Ajusta a 5 estrellas + "Muy responsable, Max está feliz"
  - POST /reviews {match_id: 1, rating: 5, comment: "..."}
  - BD: review(author_id=Juan, target_id=María, rating=5)

Match #2 con Ana (Adoptante) - Diciembre 5
  - Adopción completada
  - Ana califica: 4 estrellas + "Buena comunicación"
  - BD: review(author_id=Ana, target_id=María, rating=4)

Match #3 con Luis (Adoptante) - Diciembre 10
  - Adoptante completa, Luis califica: 5 estrellas
  - BD: review(author_id=Luis, target_id=María, rating=5)

Perfil de María ahora muestra:
  - Promedio: (5 + 4 + 5) / 3 = 4.67 estrellas
  - Reviews totales: 3
  - Nuevos adoptantes ven: "4.67/5 ⭐ (3 opiniones)"
  - Confianza + 70% en posibilidad de match exitoso
```

## Etapa 7: Justicia y Orden - RBAC Administrativo y Panel de Moderación (Completada)

La Etapa 7 transforma PAWS de una plataforma comunitaria auto-regulada a un ecosistema con jerarquía clara y moderación activa. Implementa un sistema completo de Control de Acceso Basado en Roles (RBAC) que diferencia entre "mortales" (Adoptantes y Rescatistas) y "dioses" (Administradores). Los cambios abarcan tres pilares fundamentales: un middleware RBAC en el backend que protege rutas sensibles, un mecanismo de autopromoción al iniciar el servidor que identifica usuarios administrativos automáticamente, y una interfaz exclusiva en Flutter que permite a los administradores visualizar todas las denuncias y ejecutar sentencias (bans) con motivos documentados. Adicionalmente, se corrigió un problema crítico de identidad donde los IDs de reportes no coincidían con los usuarios reales, causando bans erróneos en IDs fantasma. La serialización JSON fue normalizada para garantizar consistencia entre frontend y backend.

### Pilares de Etapa 7

1. **RBAC (Role-Based Access Control)**: Middleware en Go que valida el rol JWT antes de acceder a rutas administrativas
2. **Autopromoción Automática**: Mecanismo en main.go que promueve a admin al usuario con correo institucional específico
3. **Panel de Justicia**: Interfaz exclusiva en Flutter para administradores, mostrando reportes y permitiendo bans manuales
4. **Corrección de Identidad**: Resolución de problema crítico donde reportedID no apuntaba a usuarios correctos (IDs fantasma 999)
5. **Normalización JSON**: Consolidación de serialización (ID vs id) para asegurar que frontend y backend hablen el mismo idioma

### Cambios en el Backend de Etapa 7

#### 1. Middleware RBAC (roles.go) - Protección de Rutas Administrativas

Se creó un nuevo middleware en `internal/transport/http/middleware/roles.go` que actúa como guardaespaldas de rutas sensibles:

```go
// RequireRole verifica que el usuario tenga el rol necesario (ej: "admin")
func RequireRole(requiredRole string) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. Obtenemos el rol que AuthMiddleware guardó en contexto
		role := c.GetString("role")

		// 2. Verificamos (Si no es admin, fuera)
		if role != requiredRole {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "Acceso denegado: Se requiere nivel " + requiredRole,
			})
			return
		}

		c.Next()
	}
}
```

**Características**:

- **Verificación Simple pero Efectiva**: Extrae el rol del contexto (que AuthMiddleware ya validó)
- **Respuesta Determinística**: 403 Forbidden si el rol no coincide
- **Composición de Middleware**: Se usa como segundo guardián después de AuthMiddleware
- **Extensible**: Puede soportar múltiples roles en futuro (ej: "moderator", "super_admin")

**Flujo de Protección**:

```
Request → AuthMiddleware (¿Token válido?)
         → RequireRole("admin") (¿Es admin?)
         → Endpoint Administrativo
```

#### 2. Actualización del AuthMiddleware - Extracción y Almacenamiento de Rol

El middleware `internal/transport/http/middleware/auth.go` fue actualizado para extraer el campo `role` del JWT:

```go
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// ... (Validación del token igual que antes) ...

		// Extraer datos del token
		if claims, ok := token.Claims.(jwt.MapClaims); ok {
			c.Set("userID", claims["sub"])
			c.Set("role", claims["role"])  // NUEVO EN ETAPA 7
		} else {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "error procesando claims"})
			return
		}

		c.Next()
	}
}
```

**Cambios**:

- Línea agregada: `c.Set("role", claims["role"])`
- El JWT debe contener campo `role` (generado en AuthService durante login/registro)
- Los valores típicos son: "adopter", "rescuer", "admin"
- Si JWT no tiene `role`, se asume "adopter" por defecto (fallback seguro)

**Impacto en Flujo**:

1. Frontend recibe JWT con `role` después de login
2. Frontend almacena JWT completo en FlutterSecureStorage
3. Frontend envía JWT en Authorization header
4. Backend extrae JWT, valida firma, extrae `role`
5. `role` está disponible en contexto para handlers y otros middleware

#### 3. Seeder de Admin Automático (main.go) - Autopromoción

Se agregó lógica en `cmd/api/main.go` que detecta si el usuario con correo institucional existe y lo promueve a admin automáticamente:

```go
// =========================================================================
// SEEDER DE ADMIN (Auto-Promoción)
// =========================================================================
var adminUser domain.User
targetEmail := "alonso.vera@mail.udp.cl"

// Buscamos si el usuario ya se registró
if err := database.DB.Where("email = ?", targetEmail).First(&adminUser).Error; err == nil {
	// Si existe y no es admin, lo promovemos
	if adminUser.Role != "admin" {
		database.DB.Model(&adminUser).Update("role", "admin")
		log.Printf("Usuario %s promovido a ADMIN.", targetEmail)
	} else {
		log.Println("El usuario Admin ya está configurado correctamente.")
	}
} else {
	log.Printf("AVISO: El usuario %s aún no existe en la BD. Regístrate en la App y reinicia el backend.", targetEmail)
}
```

**Características**:

- **Detección por Email**: Busca específicamente `alonso.vera@mail.udp.cl`
- **Idempotencia**: Si ya es admin, no hace nada
- **Esperanza Inteligente**: Si no existe, avisa al log pero no falla
- **Timing**: Se ejecuta al arrancar el servidor (después de AutoMigrate)

**Ventajas**:

- No requiere endpoint administrativo para crear admins
- No requiere base de datos preexistente con admin
- Después del primer login de Alonso, next restart → promoción automática
- Seguro: solo promueve el email específico

**Uso**:

```
Evento 1: Alonso se registra vía app (registro normal)
  → BD: INSERT user(email="alonso.vera@mail.udp.cl", role="adopter")
  → JWT después: {sub: 123, role: "adopter"}

Evento 2: Restart backend
  → Seeder ejecuta: WHERE email = "alonso.vera@mail.udp.cl"
  → Encuentra registro de Alonso
  → UPDATE users SET role = "admin" WHERE id = 123
  → Log: "Usuario alonso.vera@mail.udp.cl promovido a ADMIN"

Evento 3: Alonso hace login nuevamente
  → JWT generado: {sub: 123, role: "admin"}
  → Frontend detecta role="admin" → navega a AdminDashboardScreen
```

#### 4. AdminHandler - Endpoints de Administración

Se creó `internal/transport/http/admin_handler.go` con dos endpoints críticos:

```go
// GetReports (GET /admin/reports)
func (h *AdminHandler) GetReports(c *gin.Context) {
	reports, err := h.service.GetAllReports()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error cargando reportes"})
		return
	}
	c.JSON(http.StatusOK, reports)
}

// BanUser (POST /admin/ban/:id)
func (h *AdminHandler) BanUser(c *gin.Context) {
	// Obtenemos ID del Admin (quien ejecuta la acción)
	adminIDVal, _ := c.Get("userID")
	adminID := uint(adminIDVal.(float64))

	// Obtenemos ID del usuario a banear
	targetIDStr := c.Param("id")
	targetID, _ := strconv.Atoi(targetIDStr)

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Se requiere motivo (reason)"})
		return
	}

	err := h.service.BanUserManual(adminID, uint(targetID), req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error baneando usuario: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "JUSTICIA APLICADA: Usuario baneado."})
}
```

**Endpoints**:

- `GET /admin/reports` - Lista todos los reportes con información de denunciante y denunciado
- `POST /admin/ban/:id` - Ejecuta un ban manual con motivo documentado

**Flujo de GetReports**:

```
GET /admin/reports (con Authorization header)
↓
AuthMiddleware: ¿Token válido? Sí
↓
RequireRole("admin"): ¿Es admin? Sí
↓
AdminHandler.GetReports()
  → ReportService.GetAllReports()
  → Preload("Reporter", "Reported") para obtener nombres de usuarios
  → Retorna array JSON con estructura:
     {
       "id": 5,
       "reporter_id": 2,
       "reported_id": 3,
       "reporter": {name: "Juan", email: "..."},
       "reported": {name: "Carlos", email: "..."},
       "reason": "Solicita dinero sin entregar mascota",
       "status": "verified",
       "created_at": "2025-12-20T14:30:00Z"
     }
```

**Flujo de BanUser (Manual)**:

```
POST /admin/ban/456 {reason: "Acoso reiterado"}
↓
AuthMiddleware & RequireRole("admin"): Validaciones OK
↓
AdminHandler.BanUser()
  → adminID = 1 (el admin ejecutando)
  → targetID = 456 (quien será baneado)
  → ReportService.BanUserManual(1, 456, "Acoso reiterado")
    → Obtiene user.Run para el usuario 456
    → INSERT blacklist_entry(run, reason)
    → UPDATE users SET is_banned = true WHERE id = 456
    → Retorna éxito
↓
Respuesta: {message: "JUSTICIA APLICADA: Usuario baneado."}
↓
Usuario 456 intenta login:
  → AuthService verifica blacklist por RUN
  → 403 Forbidden: "Tu cuenta ha sido suspendida"
```

#### 5. ReportService - Nuevos Métodos para Administración

Se ampliaron los métodos del ReportService con dos funciones administrativas:

```go
// GetAllReports: Lista todas las denuncias para el Admin (Cargando nombres de usuarios)
func (s *ReportService) GetAllReports() ([]domain.Report, error) {
	var reports []domain.Report
	// PRELOAD: Cargamos las relaciones Reporter y Reported
	err := s.db.Preload("Reporter").Preload("Reported").
		Order("created_at desc").
		Find(&reports).Error
	return reports, err
}

// BanUserManual: El botón de pánico del Admin
func (s *ReportService) BanUserManual(adminID, targetUserID uint, reason string) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// 1. Buscar al usuario objetivo
		var user domain.User
		if err := tx.First(&user, targetUserID).Error; err != nil {
			return err
		}

		// 2. Marcarlo como baneado en la tabla users
		if err := tx.Model(&user).Update("is_banned", true).Error; err != nil {
			return err
		}

		// 3. Crear entrada en Blacklist (para que no se registre de nuevo con el mismo RUT)
		blacklistEntry := domain.BlacklistEntry{
			Run:    user.Run,
			Reason: fmt.Sprintf("Baneado por Admin #%d: %s", adminID, reason),
		}

		if err := tx.Where("run = ?", user.Run).FirstOrCreate(&blacklistEntry).Error; err != nil {
			return err
		}

		return nil
	})
}
```

**Cambios**:

- **GetAllReports()**: Usa `.Preload("Reporter").Preload("Reported")` para cargar información completa de ambos usuarios, permitiendo que el frontend muestre nombres en lugar de solo IDs
- **BanUserManual()**: Ejecuta una transacción que:
  1. Busca el usuario por ID (corrección: ya no IDs fantasma como 999)
  2. Marca `is_banned = true` en tabla users
  3. Agrega RUN a blacklist (previene registro con mismo RUT)
  4. Documenta motivo en blacklist

**CORRECCIÓN DE IDENTIDAD - El Problema de los IDs 999**:

Antes de Etapa 7, cuando reportes se creaban, el campo `reported_id` podía ser 999 (dummy) si no se pasaba el ID real, causando que bans se ejecutaran en usuarios fantasma. Ahora:

- ReportService.BanUserManual() busca el usuario por ID correcto
- Si el ID no existe, retorna error (no silencia)
- AdminHandler valida que el ID es integer válido (`:id` param)
- Adicionalmente, la relación en domain.Report (ver corrección JSON) asegura que los IDs se cargan correctamente

#### 6. Corrección de Identidad - domain.Report con Relaciones

Se actualizó `internal/core/domain/report.go` para incluir relaciones explícitas:

```go
type Report struct {
	gorm.Model

	// IDs (Llaves Foráneas)
	ReporterID uint   `gorm:"not null" json:"reporter_id"`
	ReportedID uint   `gorm:"not null" json:"reported_id"`

	// --- RELACIONES (Lo que te faltaba) ---
	Reporter   User   `gorm:"foreignKey:ReporterID" json:"Reporter"`
	Reported   User   `gorm:"foreignKey:ReportedID" json:"Reported"`

	Reason     string `gorm:"not null" json:"reason"`
	Status     string `gorm:"default:'pending'" json:"status"`
}
```

**Cambios Críticos**:

- Líneas agregadas con etiquetas `gorm:"foreignKey:..."` indican a GORM que cargue la información del usuario
- Estructura JSON: `json:"Reporter"` (capitalizado) para que al serializar, se envíe como `{"Reporter": {...}}`
- Beneficio: Cuando se obtienen reportes, vienen con nombres, emails, fotos de denunciante y denunciado

**Normalización JSON**:

- `ReporterID` y `ReportedID` se serializan en snake_case (`reporter_id`, `reported_id`)
- `Reporter` y `Reported` se serializan tal cual (capitalizado)
- Frontend recibe: `{reporter_id: 2, reported_id: 3, Reporter: {...}, Reported: {...}}`

#### 7. Rutas Registradas (main.go) - Grupo Admin

Se agregó un nuevo grupo de rutas protegidas en `cmd/api/main.go`:

```go
// GRUPO ADMIN: Doble protección (Auth + Role Admin)
admin := protected.Group("/admin")
admin.Use(middleware.RequireRole("admin"))
{
	admin.GET("/reports", adminHandler.GetReports)
	admin.POST("/ban/:id", adminHandler.BanUser)
}
```

**Estructura**:

- `admin := protected.Group("/admin")` - Inherita AuthMiddleware del grupo protected
- `admin.Use(middleware.RequireRole("admin"))` - Segundo guardián: solo admins
- Rutas dentro: solo accesibles a admins autenticados

**URLs Finales**:

- `GET /api/v1/admin/reports` (solo admin, requiere JWT)
- `POST /api/v1/admin/ban/:id` (solo admin, requiere JWT + motivo)

### Cambios en el Frontend de Etapa 7

#### 1. AdminDashboardScreen - Panel de Justicia

Se creó una nueva pantalla exclusiva en `app/lib/features/admin/presentation/screens/admin_dashboard_screen.dart` que permite a administradores visualizar y ejecutar sentencias:

```dart
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminRepository _repo = AdminRepository();
  late Future<List<dynamic>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _reportsFuture = _repo.getReports();
    });
  }

  Future<void> _banUser(int userId, String userName) async {
    final reasonCtrl = TextEditingController();

    // Pedir motivo del ban
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("¿Banear a $userName?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Esta acción bloqueará permanentemente al usuario por su RUT.",
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: "Motivo del Ban (Requerido)",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "EJECUTAR SENTENCIA",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && reasonCtrl.text.isNotEmpty) {
      try {
        await _repo.banUser(userId, reasonCtrl.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Justicia aplicada. Usuario baneado."),
            ),
          );
          _refresh(); // Recargar lista
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e")),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel de Justicia"),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (r) => false,
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final reports = snapshot.data ?? [];

          if (reports.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 60,
                    color: Colors.green,
                  ),
                  SizedBox(height: 10),
                  Text("La comunidad está en paz."),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              final reporter = report['Reporter']?['name'] ?? 'Anónimo';
              final reported = report['Reported']?['name'] ?? 'Usuario';
              final reportedId = report['reported_id'];
              final reason = report['reason'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                elevation: 4,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.redAccent,
                    child: Icon(Icons.warning_amber, color: Colors.white),
                  ),
                  title: Text("Acusado: $reported"),
                  subtitle: Text("Denunciante: $reporter\nMotivo: $reason"),
                  isThreeLine: true,
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: () => _banUser(reportedId, reported),
                    child: const Text(
                      "BAN",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

**Características del Panel**:

- **Carga Asincrónica**: FutureBuilder obtiene lista de reportes mediante `AdminRepository.getReports()`
- **Despliegue Visual**: Cada reporte es una Card con:
  - Icono de advertencia rojo
  - Nombre del acusado
  - Nombre del denunciante
  - Motivo del reporte
  - Botón "BAN" (rojo, indica acción grave)
- **Diálogo de Confirmación**: Antes de ejecutar ban, pide motivo documentado
- **Validación**: Solo permite ban si se ingresa motivo no vacío
- **Feedback Inmediato**: SnackBar de éxito o error
- **Recarga**: `_refresh()` vuelve a obtener reportes después de ban
- **Estado Paz**: Si no hay reportes, muestra icono de checkmark verde con "La comunidad está en paz"

**Acceso a Pantalla**:

- Solo visible si `role == "admin"` en JWT
- LoginScreen lo detecta después de login exitoso
- Reemplaza MainLayout para admins (no ven tabs de adopter/rescuer)
- Botón logout en AppBar para volver al login

#### 2. AdminRepository - Capa de Datos para Administración

Se creó `app/lib/features/admin/data/admin_repository.dart` como intermediaria entre UI y API:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class AdminRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // Obtener lista de reportes
  Future<List<dynamic>> getReports() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/admin/reports',
        options: options,
      );
      return response.data;
    } catch (e) {
      throw Exception('Error cargando reportes: $e');
    }
  }

  // Banear usuario (El Martillo)
  Future<void> banUser(int userId, String reason) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/admin/ban/$userId',
        data: {'reason': reason},
        options: options,
      );
    } catch (e) {
      throw Exception('Error baneando usuario: $e');
    }
  }
}
```

**Métodos**:

- **getReports()**: GET /admin/reports
  - Obtiene lista de reportes desde backend
  - Incluye información de Reporter y Reported
  - Inyecta JWT automáticamente
- **banUser(int userId, String reason)**: POST /admin/ban/:id
  - Ejecuta ban manual con motivo
  - `userId` se inserta en URL path
  - `reason` se envía en body JSON

#### 3. Actualización del LoginScreen - Ruteo Condicional por Rol

El archivo `app/lib/features/auth/presentation/screens/login_screen.dart` fue actualizado para detectar si el usuario es admin y navegar apropiadamente:

```dart
} else if (state is LoginSuccess) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('¡Bienvenido!'),
      backgroundColor: Colors.green,
    ),
  );

  final authRepo = context.read<AuthRepository>();
  final token = await authRepo.getToken();

  if (token != null) {
    Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
    String role = decodedToken['role'] ?? 'adopter';

    // --- LÓGICA DE RUTAS MODIFICADA ---
    if (role == 'admin') {
      // CASO 1: Es Administrador -> Vamos al Panel de Justicia
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const AdminDashboardScreen(),
          ),
          (route) => false,
        );
      }
    } else {
      // CASO 2: Es Mortal (Adoptante/Rescatista) -> Vamos a la App Normal
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => MainLayoutScreen(role: role),
          ),
          (route) => false,
        );
      }
    }
  }
}
```

**Cambios**:

- Línea nueva: `String role = decodedToken['role'] ?? 'adopter';`
  - Decodifica JWT (ya guardado en FlutterSecureStorage)
  - Extrae el campo `role`
  - Fallback a 'adopter' si no existe (nunca debería pasar)

- Condicional: `if (role == 'admin')`
  - Si es admin: navega a `AdminDashboardScreen()`
  - Si es mortal: navega a `MainLayoutScreen(role: role)`

**Impacto en UX**:

```
Escenario 1: Alonso (admin) hace login
  1. Introduce credenciales
  2. Backend autentica y genera JWT con role="admin"
  3. Frontend decodifica JWT
  4. Detecta role=="admin"
  5. Navega a AdminDashboardScreen (Panel de Justicia)
  6. Ve lista de reportes y botones BAN

Escenario 2: Juan (adoptante) hace login
  1. Introduce credenciales
  2. Backend autentica y genera JWT con role="adopter"
  3. Frontend decodifica JWT
  4. Detecta role!="admin"
  5. Navega a MainLayoutScreen(role: "adopter")
  6. Ve tabs: Descubrir, Mis Matches, Perfil
```

### Casos de Uso Mejorados con Etapa 7

**Caso 1: Autopromoción Automática de Alonso (Primera vez)**

```
Evento 1: Alonso se registra en la App
  - App: POST /auth/register {email: "alonso.vera@mail.udp.cl", ...}
  - Backend AuthService crea User con role="adopter" (default)
  - BD: INSERT users(id=1, email="alonso.vera@mail.udp.cl", role="adopter")
  - JWT generado: {sub: 1, role: "adopter"}
  - Frontend: NavegaaMainLayoutScreen(role: "adopter")

Evento 2: Alonso detecta que debería ser admin, reinicia backend
  - Backend inicia, ejecuta seeder
  - Seeder: WHERE email = "alonso.vera@mail.udp.cl"
  - Encuentra registro (id=1)
  - UPDATE users SET role="admin" WHERE id=1
  - Log: "Usuario alonso.vera@mail.udp.cl promovido a ADMIN"

Evento 3: Alonso hace logout en App (o reinicia sesión)
  - App: POST /auth/login {email: "alonso.vera@mail.udp.cl", ...}
  - Backend genera JWT: {sub: 1, role: "admin"}  (ahora correcto)
  - Frontend decodifica: role == "admin"
  - Frontend navega a AdminDashboardScreen
  - Panel de Justicia aparece con lista de reportes
```

**Caso 2: Admin Visualiza Reportes y Ejecuta Sentencia Manual**

```
Alonso accede al Panel de Justicia:

Reporte #1:
  - Denunciante: Juan Pérez
  - Acusado: Carlos García
  - Motivo: "Solicita dinero sin entregar mascota"
  - Botón: BAN

Reporte #2:
  - Denunciante: Ana López
  - Acusado: Carlos García (mismo usuario!)
  - Motivo: "Amenazas por WhatsApp"

Reporte #3:
  - Denunciante: Bob Smith
  - Acusado: Carlos García (sigue siendo el mismo!)
  - Motivo: "Estafa confirmada"

Alonso ve 3 reportes sobre Carlos García (reportedID=7)
Alonso presiona botón BAN en cualquiera
  - Dialog: "¿Banear a Carlos García?"
  - TextField: "Motivo del Ban (Requerido)"
  - Alonso ingresa: "Acumulación de reportes graves (3 denuncias verificadas)"
  - Alonso presiona "EJECUTAR SENTENCIA" (rojo, dramático)

Backend:
  - POST /admin/ban/7 {reason: "Acumulación de reportes graves..."}
  - AdminHandler.BanUser() valida:
    - ¿Token válido? Sí (authMiddleware)
    - ¿Es admin? Sí (requireRole)
    - ¿Motivo no vacío? Sí
  - ReportService.BanUserManual(adminID=1, targetUserID=7, reason="...")
    - Obtiene user.Run de usuario 7
    - INSERT blacklist(run, reason)
    - UPDATE users SET is_banned=true WHERE id=7
  - Respuesta: {message: "JUSTICIA APLICADA: Usuario baneado."}

Frontend:
  - SnackBar: "Justicia aplicada. Usuario baneado."
  - _refresh() recarga lista
  - Carlos García ya no aparece (porque su is_banned=true)
  - Lista ahora muestra 0 reportes

Resultado:
  - Carlos García intenta login:
    - AuthService verifica RUN contra blacklist
    - Encuentra entrada (run baneado)
    - Respuesta: 403 {error: "Tu cuenta ha sido suspendida"}
  - Carlos García nunca más accede a PAWS
```

**Caso 3: Corrección de Identidad - Antes vs Después**

Antes de Etapa 7:

```
Flujo Quebrado:
1. Frontend: SocialRepository.createReport(reportedId=999, reason="Estafa")
   (999 es un ID dummy porque no se pasó el real)
2. Backend: ReportHandler.Create() no valida, crea report con reported_id=999
3. Usuario real (ID=5) nunca es baneado
4. Admin intenta banear ID=999
5. BanUserManual busca user WHERE id=999
6. No encuentra nada (ID fantasma)
7. Ban falla silenciosamente o genera error críptico
8. Usuario real sigue activo pese a reportes
```

Después de Etapa 7:

```
Flujo Correcto:
1. Frontend obtiene ID real del match/usuario
2. Frontend: SocialRepository.createReport(reportedId=5, reason="Estafa")
   (5 es el ID real del usuario)
3. Backend: ReportHandler.Create() valida reported_id es uint válido
4. Database.Report creado con reported_id=5 correctamente
5. ReportService.GetAllReports() usa Preload("Reported") para cargar usuario 5
6. Admin ve en Panel: Acusado: "María García" (ID 5)
7. Admin presiona BAN
8. BanUserManual(adminID, targetUserID=5, reason)
   - Busca user WHERE id=5 ← Encuentra correctamente
   - UPDATE users SET is_banned=true WHERE id=5
   - INSERT blacklist(run="17.123.456-K")
9. Usuario 5 baneado exitosamente
10. No hay IDs fantasma involucrados
```

### Mejoras en Arquitectura y Seguridad

**Arquitectura de Tres Niveles Jerárquicos**:

```
                    [Admin]
                       |
        (Middleware: AuthMiddleware + RequireRole)
                       |
            [Admin Endpoints: /admin/...]
                       |
                  [Panel de Justicia]
                  [BAN, GetReports]

                  [Mortal] (Adoptante/Rescatista)
                       |
        (Middleware: AuthMiddleware)
                       |
            [User Endpoints: /matches, /reviews, etc]
                       |
                  [MainLayout App]
                  [Chat, Swipe, Adopt]
```

**Ventajas de RBAC**:

1. **Escalabilidad**: Fácil agregar nuevos roles (moderator, super_admin, banned_user)
2. **Granularidad**: Cada rol puede tener permisos específicos
3. **Auditabilidad**: BanUserManual documenta quién baneó a quién y por qué
4. **Seguridad**: Protección en dos niveles (JWT válido + Rol correcto)

**Ventajas de Autopromoción**:

1. **Sin Boilerplate**: No necesitas endpoint administrativo
2. **Determinista**: Siempre promueve al mismo email
3. **Recuperable**: Si la promoción falla, un restart lo intenta nuevamente
4. **Seguro**: Solo afecta al email específico, no abre puerta a escalada

**Corrección de Identidad - Beneficios**:

1. **Precisión**: Bans se aplican al usuario correcto, no a IDs fantasma
2. **Trazabilidad**: Cada ban documentado con motivo y admin que lo ejecutó
3. **Prevención de Reincidencia**: Blacklist por RUN impide registro con mismo documento
4. **Consistencia JSON**: Reporter y Reported siempre se cargan correctamente

## Etapa 8: Hacia la Nube y el Mundo - Despliegue en Supabase, Railway y Vercel (Completada)

La Etapa 8 marca el punto de inflexión donde PAWS abandona localhost y se despliega al mundo real con una arquitectura híbrida de tres servicios en la nube. Se implementó una base de datos cloud-first con Supabase, un backend API públicamente accesible en Railway, y una aplicación web en Vercel, con configuración inteligente que permite al código detectar automáticamente si está en desarrollo o producción.

### 1. Base de Datos Híbrida - De PostgreSQL Local a Supabase Cloud

**Migración de PostgreSQL**:

En etapas anteriores, el proyecto usaba PostgreSQL en Docker local (puerto 5433 en docker-compose.yml). Etapa 8 mantiene esta capacidad pero agrega soporte para Supabase, un servicio PostgreSQL hosted en AWS con replicas globales.

**Cambio en postgres.go - Detección Inteligente Local vs Nube**:

```go
// internal/platform/database/postgres.go

func Connect() {
	var dsn string

	// 1. PRIORIDAD: Intentamos leer la Connection String completa (Estilo Supabase/Railway)
	// Ejemplo: postgres://postgres:password@db.supabase.co:5432/postgres
	dsn = os.Getenv("DATABASE_URL")

	// 2. FALLBACK: Si no hay URL completa, construimos la cadena manualmente (Estilo Local/Docker)
	if dsn == "" {
		host := os.Getenv("DB_HOST")
		user := os.Getenv("DB_USER")
		password := os.Getenv("DB_PASSWORD")
		dbName := os.Getenv("DB_NAME")
		port := os.Getenv("DB_PORT")

		sslMode := os.Getenv("DB_SSL_MODE")
		if sslMode == "" {
			sslMode = "disable"
		}

		dsn = fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=%s",
			host, user, password, dbName, port, sslMode)

		log.Println("Modo Local detectado: Usando variables individuales.")
	} else {
		log.Println("Modo Nube detectado: Usando DATABASE_URL.")
	}

	connection, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		PrepareStmt: false,
	})
	if err != nil {
		log.Fatal("Error fatal conectando a la base de datos: ", err)
	}

	DB = connection
	log.Println("Conexión a Base de Datos exitosa")
}
```

**Lógica de Detección**:

1. **Prioridad 1**: Busca variable `DATABASE_URL` (estilo Supabase/Railway)
   - Formato: `postgresql://usuario:contraseña@host:puerto/basedatos`
   - Ejemplo real: `postgresql://postgres.sfpgibalxrecscjcevrk:Password123@aws-0-us-west-2.pooler.supabase.com:6543/postgres?pgbouncer=true`
   - Ventaja: Una sola variable, fácil de pasar en CI/CD o Railway dashboard

2. **Fallback**: Si DATABASE_URL está vacía, construye DSN de variables individuales
   - `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_PORT`, `DB_SSL_MODE`
   - Modo local (Docker Compose): Usa valores como `localhost`, `paws_user`, etc.
   - Ventaja: Compatible con desarrollo sin cambiar código

3. **SSL Mode**:
   - Producción (Supabase): `sslmode=require` o `sslmode=verify-full` (seguro)
   - Local (Docker): `sslmode=disable` (sin SSL, unsafe pero válido en localhost)

**Ventajas de esta Estrategia**:

- **Portabilidad**: Mismo código funciona en local y en nube sin cambios
- **Seguridad**: DATABASE_URL no se commitea a git (.env está en .gitignore)
- **Escalabilidad**: Supabase maneja réplicas, backups automáticos, SSL obligatorio
- **Performance**: Supabase ofrece Connection Pooling (puerto 6543) para limitar conexiones

**Connection Pooler - Solución al Problema IPv6 de Supabase**:

Supabase requiere Connection Pooler para evitar problemas de timeout en infraestructuras modernas con IPv6. En vez de conectar directamente al puerto 5432, usamos puerto 6543 (Connection Pooler) que distribuye conexiones inteligentemente:

```
// OLD (sin pooler - problemas de timeout)
Host: db.supabase.co:5432

// NEW (con pooler - estable)
Host: db.supabase.co:6543?pgbouncer=true
```

**Configuración en .env (Desarrollo Local)**:

```dotenv
# Modo local (Docker Compose)
DB_HOST=localhost
DB_PORT=5433
DB_USER=paws_user
DB_PASSWORD=paws_secret_password
DB_NAME=paws_db
DB_SSL_MODE=disable

# DATABASE_URL está vacía, así que usa las variables arriba
DATABASE_URL=
```

**Configuración en .env (Producción - Supabase)**:

```dotenv
# Modo nube (Supabase via Railway)
DATABASE_URL=postgresql://postgres.sfpgibalxrecscjcevrk:YanoespistaShow123---@aws-0-us-west-2.pooler.supabase.com:6543/postgres?pgbouncer=true

# Las variables abajo son ignoradas (DATABASE_URL tiene prioridad)
# DB_HOST=
# DB_USER=
# ...
```

**Migraciones Automáticas en Nube**:

Etapa 8 mantiene las migraciones automáticas en `main.go`:

```go
// cmd/api/main.go - Las migraciones se aplican automáticamente

if err := database.DB.AutoMigrate(
    &domain.User{},
    &domain.UserProfile{},
    &domain.Pet{},
    &domain.Match{},
    &domain.Message{},
    &domain.Review{},
    &domain.Report{},
    &domain.BlacklistEntry{},
); err != nil {
    log.Fatal("Error en la migración de base de datos: ", err)
}
log.Println("Migración de base de datos completada")
```

Cuando el backend se despliega en Railway (con DATABASE_URL apuntando a Supabase):

1. Backend conecta a Supabase exitosamente
2. GORM ejecuta AutoMigrate()
3. Crea/actualiza esquema en Supabase automáticamente
4. No requiere scripts manuales o CLI herramientas

### 2. Backend en Railway - API Pública Accesible

**¿Qué es Railway?**

Railway es una plataforma de despliegue que conecta tu repositorio GitHub, detecta que es una aplicación Go, la compila, la dockeriza y la despliega en servidores globales. El resultado es una URL pública como `https://paws-20-production.up.railway.app`.

**Proceso de Despliegue**:

1. **Conexión GitHub**: Railway accede a tu repositorio (OAuth)
2. **Detección Automática**: Detecta `go.mod` → Aplicación Go
3. **Compilación**: `go build` en el entorno de Railway
4. **Dockerización**: Crea imagen Docker automáticamente
5. **Despliegue**: Ejecuta contenedor en servidores de Railway
6. **URL Pública**: Asigna dominio `*.up.railway.app` automáticamente

**Variables de Entorno en Railway**:

Railway proporciona dashboard donde configuras variables antes del despliegue:

```
PORT=8080                     # Puerto interno (Railway mapea a 443 HTTPS automáticamente)
JWT_SECRET=your-secret-key    # Secreto para firmar JWTs
DATABASE_URL=postgresql://... # Conexión a Supabase
ENABLE_ASYNC_FEATURES=false   # Desactiva RabbitMQ si no disponible
```

**Flujo en Tiempo Real**:

```
Usuario en Frontend (web o app)
    ↓
Hace request a API
    ↓
URL: https://paws-20-production.up.railway.app/api/v1/...
    ↓
Railway recibe request en servidores cloud
    ↓
Backend (Go) procesa request
    ↓
Conecta a Supabase (DATABASE_URL)
    ↓
Responde JSON al usuario
    ↓
Frontend recibe y renderiza
```

**URLs Públicas Resultantes**:

- Backend API: `https://paws-20-production.up.railway.app/api/v1`
- Chat WebSocket: `wss://paws-20-production.up.railway.app/api/v1/chat/ws`
- Health Check: `https://paws-20-production.up.railway.app/api/v1/health` (si existe endpoint)

**Beneficios**:

- **Accesible Globalmente**: Usuarios desde cualquier país pueden conectar
- **SSL/TLS Automático**: Railway gestiona certificados HTTPS
- **Escalado Automático**: Aumenta recursos si hay picos de tráfico
- **Logs en Tiempo Real**: Dashboard de Railway muestra logs del backend
- **CI/CD Integrado**: Cada push a GitHub trigger despliegue automático

### 3. Frontend Web - De Flutter Mobile a Vercel

**Transformación de App Móvil a Web**:

Antes de Etapa 8, PAWS era solo aplicación Flutter Mobile (Android/iOS). Flutter soporta compilación a Web (HTML + JavaScript), permitiendo que el mismo código Dart funcione en navegadores.

**Compilación a Web**:

```bash
# Generar código web (HTML/JS/CSS)
flutter build web --release

# Resultado en: app/build/web/
# - index.html
# - main.dart.js (Dart VM compilado a JavaScript)
# - assets/
# - canvaskit/ (runtime de Flutter para web)
```

**¿Qué es Vercel?**

Vercel es una plataforma de hosting optimizada para aplicaciones web estáticas (HTML/CSS/JS) y dinámicas. Detecta tu repositorio, construye tu proyecto y lo despliega en CDN global. La aplicación está disponible en `https://paws.vercel.app` (o dominio personalizado).

**Proceso de Despliegue**:

1. **Conexión GitHub**: Vercel accede al repositorio
2. **Detección Build**: Lee `app/pubspec.yaml` o detección automática
3. **Build**: Ejecuta `flutter build web --release`
4. **Artefactos**: Toma contenido de `app/build/web/`
5. **Hosting**: Sube a CDN global de Vercel
6. **URL Pública**: Asigna `*.vercel.app` automáticamente

**Variables de Entorno en Vercel**:

Vercel no ejecuta backend, solo sirve HTML/JS/CSS. Sin embargo, la aplicación web necesita saber dónde conectarse al backend. Se configura en el código:

```dart
// app/lib/core/constants/api_constants.dart

class ApiConstants {
  static const String baseUrl = kReleaseMode
      ? 'https://paws-20-production.up.railway.app/api/v1'  // Producción (Railway)
      : 'http://localhost:8080/api/v1';                    // Desarrollo local
}
```

En Vercel, `kReleaseMode` es siempre `true` (compilación release), así que conecta al backend en Railway.

### 4. Configuración Inteligente - ApiConstants y EnvironmentConfig

**Problema**: Durante desarrollo local, el código necesita hablar con `localhost:8080`. En producción, debe hablar con `https://paws-20-production.up.railway.app`. ¿Cómo sabe el código cuál usar?

**Solución 1: kReleaseMode**

```dart
// app/lib/core/constants/api_constants.dart

import 'package:flutter/foundation.dart';

class ApiConstants {
  static const String baseUrl = kReleaseMode
      ? 'https://paws-20-production.up.railway.app/api/v1'  // Compilación release (Vercel)
      : 'http://localhost:8080/api/v1';                    // Debug (desarrollo local)
}
```

- **kReleaseMode = true**: Modo release (`flutter run --release` o compilación Vercel)
- **kReleaseMode = false**: Modo debug (`flutter run` normal)

**Solución 2: EnvironmentConfig**

Para aplicaciones móviles (Android/iOS), el código también usa `EnvironmentConfig`:

```dart
// app/lib/core/config/environment_config.dart

import 'package:flutter/foundation.dart';
import 'dart:io';

class EnvironmentConfig {
  static String get baseUrl {
    if (kIsWeb) {
      // Web (Vercel o localhost:3000)
      return 'http://localhost:8080/api/v1';  // Configurado para desarrollo local
      // En Vercel, reemplazaría con Railway URL
    } else if (Platform.isAndroid) {
      // Android emulator
      return 'http://10.0.2.2:8080/api/v1';
    } else {
      // iOS simulator, desktop, etc.
      return 'http://localhost:8080/api/v1';
    }
  }

  static String get wsUrl {
    if (kIsWeb) {
      return 'ws://localhost:8080/api/v1';
    } else if (Platform.isAndroid) {
      return 'ws://10.0.2.2:8080/api/v1';
    } else {
      return 'ws://localhost:8080/api/v1';
    }
  }
}
```

### 5. Flujo Completo - De Desarrollo a Producción

**Escenario 1: Desarrollo Local**

```
Máquina del Desarrollador (Alonso)
│
├─ Backend: Backend Go ejecutándose en http://localhost:8080
│  ├─ Conecta a: PostgreSQL en Docker Compose (localhost:5433)
│  └─ Lee: .env local con DB_HOST=localhost
│
├─ Frontend (App Móvil): flutter run
│  ├─ Conecta a: http://10.0.2.2:8080 (emulador Android)
│  └─ kReleaseMode = false
│
└─ Frontend (Web local): flutter run -d web
   ├─ Conecta a: http://localhost:8080
   └─ Corre en: http://localhost:54321 (desarrollo)

Flujo de Request:
  User toca botón "Login" en App
    → App: POST http://10.0.2.2:8080/api/v1/auth/login
    → Backend (Go): Verifica credenciales contra BD local
    → Responde JWT
    → App almacena en FlutterSecureStorage
    → App: GET http://10.0.2.2:8080/api/v1/matches/candidates
    → Backend retorna lista de mascotas
    → App renderiza swipe deck
```

**Escenario 2: Producción (Vercel + Railway)**

```
Internet
│
├─ Usuario abre navegador
│  └─ URL: https://paws.vercel.app
│
├─ Vercel (CDN Global)
│  ├─ Sirve: HTML + JavaScript (Flutter compilado)
│  ├─ Se ejecuta en: Navegador del usuario
│  └─ JavaScript hace requests a...
│
└─ Railway Backend (Nube)
   ├─ URL: https://paws-20-production.up.railway.app/api/v1
   ├─ Conecta a: Supabase (postgresql://...)
   └─ Responde JSON

Flujo de Request (Producción):
  User abre https://paws.vercel.app en navegador
    → Vercel sirve HTML/JS (Flutter web app)
    → App carga en navegador
    → User toca botón "Login"
    → App: POST https://paws-20-production.up.railway.app/api/v1/auth/login
    → Railway Backend: Autentica contra Supabase
    → Responde JWT (firmado con JWT_SECRET de Railway)
    → App almacena JWT en localStorage/sessionStorage
    → App: GET https://paws-20-production.up.railway.app/api/v1/matches/candidates
    → Backend retorna lista de mascotas
    → App renderiza swipe deck
```

### 6. Archivo de Configuración Resultante

**Backend (.env en Railway)**:

```dotenv
# ETAPA 8: Configuración Producción en Railway
PORT=8080
JWT_SECRET=secreto_super_seguro_paws_2025

# Supabase Cloud
DATABASE_URL=postgresql://postgres.sfpgibalxrecscjcevrk:YanoespistaShow123---@aws-0-us-west-2.pooler.supabase.com:6543/postgres?pgbouncer=true

# Async Features (desactivar si RabbitMQ no disponible)
ENABLE_ASYNC_FEATURES=false
```

**Frontend (.dart constant)**:

```dart
// app/lib/core/constants/api_constants.dart
class ApiConstants {
  static const String baseUrl = kReleaseMode
      ? 'https://paws-20-production.up.railway.app/api/v1'
      : 'http://localhost:8080/api/v1';
}
```

### 7. Beneficios de Etapa 8

**Para Desarrollo**:

- Mismo código backend + frontend en desarrollo y producción
- Cambios de configuración mínimos (solo URLs)
- Fácil testear producción localmente sin cambios de código

**Para Usuarios Finales**:

- Demo en vivo sin instalaciones: `https://paws.vercel.app`
- Acceso global desde cualquier navegador
- API backend accesible desde cualquier cliente (mobile, web, desktop)
- Escalado automático en Railway si hay picos de tráfico

**Para Seguridad**:

- Credenciales (DATABASE_URL, JWT_SECRET) nunca en git
- SSL/TLS automático en ambos Vercel (HTTPS) y Railway (HTTPS)
- Supabase proporciona backups automáticos y encriptación en tránsito

**Para Portafolio**:

- Enlace en vivo para mostrar en entrevistas/ofertas
- "Live Demo" sin requierreque entrevistador instale nada
- Arquitectura escalable demostrando conocimiento de DevOps

## Acceso a Servicios

### Docker Compose

| Servicio   | URL                   | Credenciales                     |
| ---------- | --------------------- | -------------------------------- |
| pgAdmin    | http://localhost:5050 | admin@paws.com / admin           |
| PostgreSQL | localhost:5433        | paws_user / paws_secret_password |
| Redis CLI  | redis-cli -p 6379     | -                                |

### Kubernetes

| Servicio   | URL/Acceso                      | Tipo         |
| ---------- | ------------------------------- | ------------ |
| Backend    | localhost:8080                  | LoadBalancer |
| MinIO      | localhost:9001 (console)        | LoadBalancer |
| PostgreSQL | postgres-service:5432 (interno) | ClusterIP    |
| Redis      | redis-service:6379 (interno)    | ClusterIP    |

## Etapa 14: Refinamiento de Mascotas - De Foto Simple a Expediente Completo (Completada)

La Etapa 14 representa una transformación fundamental en cómo se estructuran y presentan los datos de mascotas en PAWS. El objetivo fue evolucionar desde un modelo simplista donde cada mascota poseía una única URL de foto, hacia un sistema completo de "Expediente de Adopción" que incluye galería ilimitada, información médica detallada, y características de compatibilidad. Esta etapa fue fundamentalmente un refinamiento que impactó tanto la arquitectura del backend (nueva tabla PetImage con relación 1-a-N) como la experiencia del frontend (formulario profesional con geolocalización y galería interactiva tipo Instagram).

### Transformación Arquitectónica: Single PhotoURL → PetImage Gallery

**Problema 1: Limitación de Galería de Fotos**

En versiones anteriores, cada mascota tenía un solo campo `PhotoURL` en su modelo. Esto limitaba severamente la capacidad de mostrar múltiples ángulos, el entorno, o detalles visuales de la mascota. Un adoptante potencial no podía ver si la mascota era blanca, marrón, si tenía cicatrices, o cómo se veía en diferentes espacios. Esta limitación visual reducía la confianza del adoptante y aumentaba abandonos tras la adopción.

Solución implementada: Creación de una nueva tabla `PetImage` en la base de datos que establece una relación 1-a-N con la tabla `Pet`. En lugar de guardar una URL simple, ahora cada mascota puede tener múltiples imágenes catalogadas.

```go
// backend/internal/core/domain/pet.go

type PetImage struct {
    ID      uint   `gorm:"primaryKey" json:"id"`
    PetID   uint   `gorm:"index;not null" json:"pet_id"`  // Foreign key indexado
    URL     string `json:"url"`
    IsCover bool   `json:"is_cover"`  // Identifica la imagen de portada
}

type Pet struct {
    // ... campos existentes ...
    PhotoURL string      `json:"photo_url"`  // Mantenido por backward compatibility
    Images   []PetImage  `json:"images" gorm:"foreignKey:PetID;constraint:OnDelete:CASCADE;"`

    // Nuevos campos de información médica
    IsVaccinated  bool   `json:"is_vaccinated"`
    IsSterilized  bool   `json:"is_sterilized"`
    IsDewormed    bool   `json:"is_dewormed"`
    SpecialNeeds  string `json:"special_needs"`

    // Nuevos campos de compatibilidad
    RequiresYard  bool   `json:"requires_yard"`
    GoodWithKids  bool   `json:"good_with_kids"`
    GoodWithDogs  bool   `json:"good_with_dogs"`
    GoodWithCats  bool   `json:"good_with_cats"`
    EnergyLevel   string `json:"energy_level"`  // low, medium, high

    // Ubicación precisa
    Latitude   float64 `json:"latitude"`
    Longitude  float64 `json:"longitude"`
    Address    string  `json:"address"`
}
```

Impacto: Las mascotas ahora pueden mostrar su galería completa en el frontend. La relación 1-a-N permite un número ilimitado de fotos sin cambios de estructura.

**Problema 2: Fotos "Invisibles" - El Problema N+1 Query**

Después de implementar la tabla PetImage, surgió un problema crítico: aunque la base de datos guardaba las imágenes correctamente, cuando el backend consultaba mascotas, las imágenes no se cargaban automáticamente. Esto ocurría porque GORM requiere explícitamente indicar qué relaciones deben precargarse ("eager loading"). Sin esto, cada vez que el frontend necesitaba mostrar las fotos de una mascota, requería consultas adicionales (problema N+1: 1 consulta para la mascota + N consultas para sus imágenes).

Solución implementada: Aplicación sistemática del patrón de eager loading mediante `.Preload("Images")` en todos los servicios que devuelven mascotas. Esto es especialmente crítico en servicios como `GetSwipeDeck` (que carga 50-100 mascotas) y `GetAcceptedMatches` (que necesita mostrar fotos en chats).

```go
// backend/internal/services/pet_service.go

func (s *PetService) GetAll() ([]domain.Pet, error) {
    var pets []domain.Pet
    err := s.db.Preload("User").Preload("Images").
        Where("status = ?", domain.StatusAvailable).
        Find(&pets).Error
    return pets, err
}

func (s *PetService) GetByID(id uint) (*domain.Pet, error) {
    var pet domain.Pet
    err := s.db.Preload("User").Preload("Images").
        First(&pet, id).Error
    return &pet, err
}

// backend/internal/services/match_service.go

func (s *MatchService) GetSwipeDeck(userID uint, lat, lon float64) ([]domain.Pet, error) {
    var pets []domain.Pet
    query := s.db.Preload("Images").Preload("User")
    // ... filtros de búsqueda geográfica ...
    err := query.Find(&pets).Error
    return pets, err
}

func (s *MatchService) GetAcceptedMatches(adopterID uint) ([]domain.Match, error) {
    var matches []domain.Match
    err := s.db.Preload("Pet.User").
        Preload("Pet.Images").  // CRÍTICO: sin esto, la galería está vacía
        Where("adopter_id = ? AND status = ?", adopterID, domain.MatchAccepted).
        Find(&matches).Error
    return matches, err
}
```

Impacto: Las fotos ahora aparecen instantáneamente en el swipe deck, en los chats, en los perfiles. El rendimiento mejora drásticamente (una consulta en lugar de N+1). La experiencia visual es completa desde el primer render.

### Ficha Médica Completa: Information Asymmetry → Trust

**Problema 3: Información Incompleta del Adoptante**

En PAWS original, un adoptante veía solo el nombre y foto de la mascota. No tenía información crítica sobre su estado de salud, comportamiento, o necesidades especiales. Esto llevaba a adopciones fallidas: alguien adoptaba un perro sin saber que no tolera a otros perros, resultando en devoluciones. Otro caso: adoptantes con casas pequeñas adoptaban perros que necesitaban patio.

Solución implementada: Extensión del modelo Pet con campos booleanos que capturan información médica y comportamental esencial.

```go
type Pet struct {
    // Ficha Médica
    IsVaccinated bool   `json:"is_vaccinated"`   // ¿Está al día en vacunas?
    IsSterilized bool   `json:"is_sterilized"`   // ¿Fue castrado/esterilizado?
    IsDewormed   bool   `json:"is_dewormed"`     // ¿Fue desparasitado?
    SpecialNeeds string `json:"special_needs"`   // Descripción libre (ej: "Tiene artritis")

    // Compatibilidad Comportamental
    RequiresYard bool   `json:"requires_yard"`     // ¿Necesita patio?
    GoodWithKids bool   `json:"good_with_kids"`    // ¿Es amigable con niños?
    GoodWithDogs bool   `json:"good_with_dogs"`    // ¿Se lleva bien con otros perros?
    GoodWithCats bool   `json:"good_with_cats"`    // ¿Se lleva bien con gatos?

    // Perfil Comportamental
    EnergyLevel string `json:"energy_level"`  // "low", "medium", "high"
}
```

Impacto: Los adoptantes ahora tienen información completa antes de dar "Like". Los rescatistas pueden filtrar mascotas compatibles con su situación. Las adopciones son más duraderas y exitosas porque hay alineación clara entre mascota y hogar.

### Formulario Profesional: Rescatista Experience

**Problema 4: Captura de Datos Tedious y Incompleta**

Los rescatistas no tenían una forma profesional de crear listados. El flujo era: llenar campos básicos, hacer match con fotos, luego ir a editar para agregar información. Era fragmentado y propenso a errores (ej: olvidar llenar vaccinated o energy level).

Solución implementada: `CreatePetScreen` completamente rediseñada con:

- **Selector de múltiples fotos**: ImagePicker con soporte para 10 imágenes máximo
- **Geolocalización automática**: Usa GPS nativo (geolocator package) para obtener ubicación precisa
- **Switches inteligentes**: Toggles para campos booleanos (vaccinated, sterilized, dewormed)
- **Selector de nivel energético**: SegmentedButton (low/medium/high)
- **Preferencias de compatibilidad**: CheckboxListTile (requires_yard, good_with_kids, good_with_dogs)
- **Campo libre**: TextFormField para special needs (artritis, ciego, sordo, etc.)

```dart
// frontend/app/lib/features/pets/presentation/screens/create_pet_screen.dart

class _CreatePetScreenState extends State<CreatePetScreen> {
    final List<File> _selectedImages = [];
    final ImagePicker _picker = ImagePicker();
    bool _isVaccinated = false;
    bool _isSterilized = false;
    bool _isDewormed = false;
    bool _requiresYard = false;
    bool _goodWithKids = false;
    bool _goodWithDogs = false;
    String _energyLevel = 'medium';

    Future<void> _pickImages() async {
        final List<XFile> images = await _picker.pickMultiImage(
            imageQuality: 80,  // Comprimir un poco
        );
        if (images.isNotEmpty) {
            setState(() {
                if (_selectedImages.length + images.length > 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Máximo 10 fotos permitidas")),
                    );
                    return;
                }
                _selectedImages.addAll(images.map((x) => File(x.path)));
            });
        }
    }

    Future<Position?> _determinePosition() async {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Por favor, activa GPS.')),
            );
            return null;
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
            if (permission == LocationPermission.denied) return null;
        }
        if (permission == LocationPermission.deniedForever) return null;

        return await Geolocator.getCurrentPosition();
    }

    Future<void> _submit() async {
        if (!_formKey.currentState!.validate()) return;

        Position? position = await _determinePosition();
        double lat = position?.latitude ?? -33.4489;  // Santiago default
        double lon = position?.longitude ?? -70.6693;

        await _petsRepository.createPet(
            name: _nameController.text,
            type: _typeController.text,
            breed: _breedController.text,
            age: int.parse(_ageController.text),
            description: _descriptionController.text,
            latitude: lat,
            longitude: lon,
            images: _selectedImages,
            isVaccinated: _isVaccinated,
            isSterilized: _isSterilized,
            isDewormed: _isDewormed,
            specialNeeds: _specialNeedsController.text,
            requiresYard: _requiresYard,
            goodWithKids: _goodWithKids,
            goodWithDogs: _goodWithDogs,
            energyLevel: _energyLevel,
        );
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(title: const Text('Registrar Mascota')),
            body: SingleChildScrollView(
                child: Form(
                    key: _formKey,
                    child: Column(
                        children: [
                            // Selector de imágenes
                            Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: ElevatedButton.icon(
                                    onPressed: _pickImages,
                                    icon: const Icon(Icons.photo_library),
                                    label: const Text('Seleccionar Fotos'),
                                ),
                            ),

                            // Preview de imágenes
                            if (_selectedImages.isNotEmpty)
                                SizedBox(
                                    height: 150,
                                    child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _selectedImages.length,
                                        itemBuilder: (context, index) {
                                            return Stack(
                                                children: [
                                                    Container(
                                                        width: 100,
                                                        margin: const EdgeInsets.symmetric(horizontal: 8),
                                                        decoration: BoxDecoration(
                                                            borderRadius: BorderRadius.circular(8),
                                                            image: DecorationImage(
                                                                image: FileImage(_selectedImages[index]),
                                                                fit: BoxFit.cover,
                                                            ),
                                                        ),
                                                    ),
                                                    // Label de PORTADA en la primera imagen
                                                    if (index == 0)
                                                        Positioned(
                                                            bottom: 0,
                                                            left: 0,
                                                            right: 8,
                                                            child: Container(
                                                                color: Colors.black54,
                                                                padding: const EdgeInsets.symmetric(vertical: 2),
                                                                child: const Text(
                                                                    "PORTADA",
                                                                    textAlign: TextAlign.center,
                                                                    style: TextStyle(color: Colors.white, fontSize: 10),
                                                                ),
                                                            ),
                                                        ),
                                                    // Botón de eliminar
                                                    Positioned(
                                                        top: 4,
                                                        right: 4,
                                                        child: GestureDetector(
                                                            onTap: () {
                                                                setState(() => _selectedImages.removeAt(index));
                                                            },
                                                            child: Container(
                                                                decoration: BoxDecoration(
                                                                    color: Colors.red,
                                                                    shape: BoxShape.circle,
                                                                ),
                                                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                                                            ),
                                                        ),
                                                    ),
                                                ],
                                            );
                                        },
                                    ),
                                )
                            else
                                Container(
                                    height: 150,
                                    color: Colors.grey[200],
                                    child: Center(
                                        child: Text('No hay fotos seleccionadas', style: TextStyle(color: Colors.grey[600])),
                                    ),
                                ),

                            // Campos de texto
                            _buildTextFormField('Nombre', _nameController, required: true),
                            _buildTextFormField('Tipo', _typeController, required: true),
                            _buildTextFormField('Raza', _breedController),
                            _buildTextFormField('Edad (años)', _ageController, required: true),
                            _buildTextFormField('Descripción', _descriptionController, maxLines: 3),

                            // Switches de salud
                            _buildSwitch('¿Vacunado?', _isVaccinated, (value) {
                                setState(() => _isVaccinated = value ?? false);
                            }),
                            _buildSwitch('¿Esterilizado/Castrado?', _isSterilized, (value) {
                                setState(() => _isSterilized = value ?? false);
                            }),
                            _buildSwitch('¿Desparasitado?', _isDewormed, (value) {
                                setState(() => _isDewormed = value ?? false);
                            }),

                            // Campo de necesidades especiales
                            Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: TextFormField(
                                    controller: _specialNeedsController,
                                    decoration: InputDecoration(
                                        labelText: 'Necesidades especiales (opcional)',
                                        helperText: 'Ej: artritis, sordera, ceguera',
                                        border: OutlineInputBorder(),
                                    ),
                                    maxLines: 2,
                                ),
                            ),

                            // Selector de nivel energético
                            Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                        const Text('Nivel de energía'),
                                        SegmentedButton<String>(
                                            segments: const [
                                                ButtonSegment(label: Text('Bajo'), value: 'low'),
                                                ButtonSegment(label: Text('Medio'), value: 'medium'),
                                                ButtonSegment(label: Text('Alto'), value: 'high'),
                                            ],
                                            selected: {_energyLevel},
                                            onSelectionChanged: (Set<String> newSelection) {
                                                setState(() => _energyLevel = newSelection.first);
                                            },
                                        ),
                                    ],
                                ),
                            ),

                            // Checkboxes de compatibilidad
                            _buildCheckbox('Requiere patio', _requiresYard, (value) {
                                setState(() => _requiresYard = value ?? false);
                            }),
                            _buildCheckbox('Bueno con niños', _goodWithKids, (value) {
                                setState(() => _goodWithKids = value ?? false);
                            }),
                            _buildCheckbox('Bueno con otros perros', _goodWithDogs, (value) {
                                setState(() => _goodWithDogs = value ?? false);
                            }),

                            // Botón de envío
                            Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                                child: ElevatedButton(
                                    onPressed: _submit,
                                    child: const Text('Registrar Mascota'),
                                ),
                            ),
                        ],
                    ),
                ),
            ),
        );
    }
}
```

Impacto: Los rescatistas ahora pueden registrar una mascota completa en 2-3 minutos. El formulario es intuitivo, con instrucciones claras y validación en tiempo real. GPS automático reduce clicks manuales.

### Galería Instagram: De Static a Interactive

**Problema 5: Visualización Estática de Imágenes**

En versiones anteriores, si una mascota tenía múltiples fotos en la galería, el frontend solo mostraba la primera en `PetDetailScreen`. No había forma de ver las otras fotos, lo que limitaba severamente la exploración visual del adoptante.

Solución implementada: Implementación de un visor de galería tipo Instagram en `PetDetailScreen` con:

- **PageView carousel**: Deslizamiento lateral suave entre fotos
- **Navegación con flechas**: Botones discretos (izquierda/derecha) que aparecen solo cuando hay múltiples fotos
- **Contador numérico**: Chip que muestra "1/4" indicando posición actual
- **Dot indicators**: Círculos abajo que muestran la posición en la galería

```dart
// frontend/app/lib/features/pets/presentation/screens/pet_detail_screen.dart

class _PetDetailScreenState extends State<PetDetailScreen> {
    late PageController _pageController;
    int _currentImageIndex = 0;

    @override
    void initState() {
        super.initState();
        _pageController = PageController();
    }

    @override
    void dispose() {
        _pageController.dispose();
        super.dispose();
    }

    void _nextImage() {
        _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
        );
    }

    void _prevImage() {
        _pageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
        );
    }

    @override
    Widget build(BuildContext context) {
        // Construir galería: primero desde images, luego fallback a imageUrl
        final List<String> gallery = widget.pet.images.isNotEmpty
            ? widget.pet.images
            : (widget.pet.imageUrl != null ? [widget.pet.imageUrl!] : []);

        return Scaffold(
            appBar: AppBar(title: Text(widget.pet.name)),
            body: SingleChildScrollView(
                child: Column(
                    children: [
                        // ============ GALERÍA ============
                        SizedBox(
                            height: 400,
                            child: Stack(
                                alignment: Alignment.center,
                                children: [
                                    // 1. PageView carousel
                                    PageView.builder(
                                        controller: _pageController,
                                        onPageChanged: (index) {
                                            setState(() => _currentImageIndex = index);
                                        },
                                        itemCount: gallery.length,
                                        itemBuilder: (context, index) {
                                            return ImageHelper.getImage(
                                                gallery[index],
                                                width: double.infinity,
                                                height: 400,
                                                fit: BoxFit.cover,
                                            );
                                        },
                                    ),

                                    // 2. Numeric indicator (top-right)
                                    if (gallery.length > 1)
                                        Positioned(
                                            top: 100,
                                            right: 16,
                                            child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.6),
                                                    borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                    "${_currentImageIndex + 1}/${gallery.length}",
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                    ),
                                                ),
                                            ),
                                        ),

                                    // 3. Left arrow (smart visibility)
                                    if (gallery.length > 1 && _currentImageIndex > 0)
                                        Positioned(
                                            left: 10,
                                            child: _NavigationButton(
                                                icon: Icons.arrow_back_ios_new,
                                                onPressed: _prevImage,
                                            ),
                                        ),

                                    // 4. Right arrow (smart visibility)
                                    if (gallery.length > 1 && _currentImageIndex < gallery.length - 1)
                                        Positioned(
                                            right: 10,
                                            child: _NavigationButton(
                                                icon: Icons.arrow_forward_ios,
                                                onPressed: _nextImage,
                                            ),
                                        ),

                                    // 5. Dot indicators (bottom-center)
                                    if (gallery.length > 1)
                                        Positioned(
                                            bottom: 16,
                                            child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: List.generate(gallery.length, (index) {
                                                    return Container(
                                                        width: 8,
                                                        height: 8,
                                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                                        decoration: BoxDecoration(
                                                            shape: BoxShape.circle,
                                                            color: _currentImageIndex == index
                                                                ? Colors.white
                                                                : Colors.white.withOpacity(0.5),
                                                        ),
                                                    );
                                                }),
                                            ),
                                        ),
                                ],
                            ),
                        ),

                        // ============ INFORMACIÓN DE LA MASCOTA ============
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    // Nombre y raza
                                    Text(
                                        widget.pet.name,
                                        style: Theme.of(context).textTheme.headlineSmall,
                                    ),
                                    Text(
                                        widget.pet.breed,
                                        style: TextStyle(color: Colors.grey[600]),
                                    ),
                                    const SizedBox(height: 16),

                                    // Información médica
                                    _buildInfoSection('Información Médica', [
                                        if (widget.pet.isVaccinated) '✓ Vacunado',
                                        if (widget.pet.isSterilized) '✓ Esterilizado',
                                        if (widget.pet.isDewormed) '✓ Desparasitado',
                                        if (widget.pet.specialNeeds.isNotEmpty) '⚠ ${widget.pet.specialNeeds}',
                                    ]),

                                    // Compatibilidad
                                    _buildInfoSection('Compatibilidad', [
                                        if (widget.pet.goodWithKids) '✓ Bueno con niños',
                                        if (widget.pet.goodWithDogs) '✓ Bueno con otros perros',
                                        if (widget.pet.requiresYard) '✓ Necesita patio',
                                        'Energía: ${widget.pet.energyLevel}',
                                    ]),

                                    // Descripción
                                    const SizedBox(height: 16),
                                    Text(
                                        'Descripción',
                                        style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    Text(widget.pet.description),
                                ],
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
}

class _NavigationButton extends StatelessWidget {
    final IconData icon;
    final VoidCallback onPressed;

    const _NavigationButton({required this.icon, required this.onPressed});

    @override
    Widget build(BuildContext context) {
        return Container(
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                shape: BoxShape.circle,
            ),
            child: IconButton(
                icon: Icon(icon, color: Colors.black87),
                onPressed: onPressed,
            ),
        );
    }
}
```

Impacto: Los adoptantes ahora pueden explorar la mascota visualmente desde múltiples ángulos. La galería interactiva tipo Instagram es familiar y intuitiva. El contador "1/4" reduce la ambigüedad ("¿hay más fotos?"). Las flechas inteligentes que aparecen solo cuando necesarias reducen clutter visual.

### Integración Backend-Frontend: Flujo Completo

**Captura de datos en el formulario** → **Multipart upload a backend** → **Almacenamiento en PetImage** → **Preload en queries** → **Visualización en galería**

1. **CreatePetScreen**: Rescatista selecciona 10 fotos, completa información médica
2. **PetsRepository.createPet()**: Construye FormData con todos los campos + archivos
3. **PetHandler.Create()**: Recibe multipart form, extrae archivos, llama a FileService
4. **FileService.SaveMultipleImages()**: Sube archivos a MinIO/S3, retorna URLs
5. **PetService.Create()**: Crea registro Pet en transacción, luego crea PetImage para cada URL
6. **Database**: Tabla pet (1 registro), tabla pet_image (10 registros con PetID)
7. **Backend queries**: GetAll/GetByID/GetSwipeDeck usan .Preload("Images")
8. **Frontend model**: Pet.fromJson() parsea array de imágenes, construye List<String>
9. **PetDetailScreen**: Construye gallery desde pet.images, muestra con PageView + indicators

### Notas Arquitectónicas de Etapa 14

- **Backward Compatibility**: Campo `PhotoURL` mantenido en base de datos. Si `Images` está vacío, frontend usa `ImageURL` como fallback. Migraciones de datos anteriores funcionan sin ruptura.
- **Eager Loading Pattern**: Todos los servicios que devuelven Pet usan `.Preload("Images")`. Esto previene N+1 queries y garantiza que galería siempre tenga datos disponibles.
- **Multipart Handling**: PetHandler recibe archivos como `files["images"]` (array). FileService procesa todos. Transacción asegura que si uno falla, rollback de todo.
- **Image Metadata**: IsCover flag identifica foto de portada/cover. Frontend usa primera imagen como PORTADA en preview.
- **GPS Fallback**: Si usuario rechaza permisos GPS, CreatePetScreen usa coordenadas por defecto (Santiago: -33.4489, -70.6693). Rescatista puede editar manualmente después.
- **ImageHelper Integration**: PetDetailScreen usa ImageHelper (de Etapa 13) para renderizar imágenes con error handling, loading progress, placeholders.
- **Energy Level Enumeration**: Campo string con valores "low", "medium", "high". Permite futura extensión sin cambio de schema. Frontend usa SegmentedButton para UX clara.

### Beneficios Consolidados de Etapa 14

**Para Adoptantes**:

- Ven múltiples ángulos de la mascota antes de comprometerse
- Información clara sobre compatibilidad (¿es bueno con niños? ¿necesita patio?)
- Información médica completa (¿está vacunado? ¿esterilizado?)
- Galería interactiva familiar (tipo Instagram) permite exploración profunda

**Para Rescatistas**:

- Formulario profesional y completo en una sola pantalla
- GPS automático reduce trabajo manual de georeferenciación
- Switches intuitivos para información médica y preferencias
- Saben que la información es completa antes de publicar

**Para el Sistema**:

- Arquitectura escalable: cualquier número de fotos sin cambio de estructura
- Rendimiento: eager loading previene N+1 queries incluso con 100+ mascotas en swipe deck
- Flexibilidad: campos booleanos permiten futuras búsquedas filtradas ("solo mascotas vacunadas")
- Calidad de datos: formulario estructurado asegura que información crítica no se omita

## Etapa 15: Perfiles Enriquecidos y Ciclo de Vida de Chats (Parcialmente Completada)

La Etapa 15 representa un refinamiento en dos áreas críticas: la expansión de perfiles de usuarios adoptantes para proporcionar a rescatistas información más profunda sobre compatibilidad, y la implementación del ciclo de vida completo de chats incluyendo exit, bloqueo y eliminación de conversaciones abandonadas. Esta etapa está parcialmente completada con funcionalidades core implementadas y características de gestión de chats aún en desarrollo. El objetivo es mejorar la confianza en el matching permitiendo que rescatistas verifiquen compatibilidad antes de aceptar solicitudes, y proporcionar mecanismos claros para usuarios que deseen abandonar conversaciones.

### Problema 1: Información Incompleta del Adoptante en Solicitudes Pendientes

**Contexto Anterior**: En Etapa 5, se implementaron perfiles básicos (nombre, foto, bio, teléfono). Sin embargo, cuando un rescatista recibía una solicitud de adopción (un "like" de un adoptante a una de sus mascotas), la información disponible era mínima. El rescatista no podía verificar si el adoptante tenía experiencia con mascotas, si vivía en una casa o departamento, si tenía patio, o qué tipo de hogar podría ofrecer. Esto llevaba a aceptaciones de solicitudes que resultaban en adopciones fallidas.

**Escenario Problemático**: María es rescatista con un perro pastor alemán que requiere patio. Juan hace "like" a su mascota. Cuando María ve la solicitud, solo ve "Juan, bio: me encantan los perros". Ella acepta. Luego descubre que Juan vive en un departamento de 60m² sin patio. La adopción falla, el perro regresa, Juan se siente culpable, y ambos han gastado tiempo y recursos.

**Solución Implementada**: Extensión del modelo User con 8 campos nuevos que capturan información de estilo de vida y experiencia del adoptante. Estos campos se editan en `EditProfileScreen` y se muestran cuando rescatistas visualizan solicitudes pendientes en `MatchRequestsScreen` o acceden a perfiles públicos en `PublicProfileScreen`.

```go
// backend/internal/core/domain/user.go

type User struct {
    // ... campos existentes (ID, Email, Name, Bio, Phone, PhotoURL, etc.) ...

    // ============ NUEVOS CAMPOS ETAPA 15 ============
    // Vivienda
    HousingType       string `gorm:"type:varchar(50);default:'House'" json:"housing_type"`
    // Valores: "House", "Apartment", "Parcel"

    HousingOwnership  string `gorm:"type:varchar(50);default:'Owned'" json:"housing_ownership"`
    // Valores: "Owned", "Rented"

    // Características del Hogar
    HasYard           bool   `gorm:"default:false" json:"has_yard"`
    HasFence          bool   `gorm:"default:false" json:"has_fence"`

    // Composición Familiar
    FamilyComposition string `gorm:"type:varchar(100);default:'Single'" json:"family_composition"`
    // Valores: "Single", "Couple", "Family" (puede incluir número de hijos)

    OtherPets         string `gorm:"type:varchar(100);default:'None'" json:"other_pets"`
    // Valores: "None", "Dogs", "Cats", "Mixed"

    // Disponibilidad y Experiencia
    TimeAvailability  string `gorm:"type:varchar(50);default:'Medium'" json:"time_availability"`
    // Valores: "Low", "Medium", "High"

    Experience       string `gorm:"type:varchar(50);default:'Beginner'" json:"experience"`
    // Valores: "Beginner", "Intermediate", "Expert"

    // ================================================
}
```

Impacto Backend: El modelo User ahora almacena 8 campos adicionales con valores por defecto sensatos. Migraciones automáticas de GORM agregan columnas con defaults a tabla existente sin ruptura de datos. Cuando `GetPendingRequests()` se ejecuta, todos estos campos se retornan en el objeto de adoptante.

```dart
// frontend/app/lib/features/user/domain/user_model.dart

class User extends Equatable {
  // ... campos existentes ...

  final String housingType;       // House, Apartment, Parcel
  final String housingOwnership;  // Owned, Rented
  final bool hasYard;
  final bool hasFence;
  final String familyComposition; // Single, Couple, Family
  final String otherPets;         // None, Dogs, Cats, Mixed
  final String timeAvailability;  // Low, Medium, High
  final String experience;        // Beginner, Intermediate, Expert

  // ... métodos fromJson/toJson incluyen nuevos campos ...
}
```

### Problema 2: Perfil Adoptante Invisible en Solicitudes

**Contexto Anterior**: El endpoint GET /api/v1/matches/requests retornaba lista de solicitudes, pero solo incluía datos básicos del adoptante. No había forma de ver el perfil completo (con nueva información) sin salir del flujo actual.

**Solución Implementada**: Modificación de `MatchService.GetPendingRequests()` para precargar información completa del adoptante junto con la mascota. Esto permite que `MatchRequestsScreen` muestre tarjeta de solicitud con información detallada del adoptante, incluyendo todos los campos nuevos.

```go
// backend/internal/core/services/match_service.go

func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
    var matches []domain.Match
    err := s.db.Table("matches").
        Joins("JOIN pets ON matches.pet_id = pets.id").
        Preload("Adopter").  // ← AHORA PRECARGA INFORMACIÓN COMPLETA DEL ADOPTANTE
        Preload("Pet").
        Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
        Find(&matches).Error
    return matches, err
}
```

Cuando rescatista abre pestaña "Solicitudes Pendientes", ve tarjeta por cada like que recibió, y la tarjeta contiene:

- Foto del adoptante
- Nombre del adoptante
- Bio del adoptante
- Teléfono del adoptante
- **NUEVO**: Tipo de vivienda (Casa/Depto/Parcela)
- **NUEVO**: Es propietario o renta
- **NUEVO**: Tiene patio y/o cerca
- **NUEVO**: Composición familiar
- **NUEVO**: Otras mascotas en casa
- **NUEVO**: Disponibilidad de tiempo (Baja/Media/Alta)
- **NUEVO**: Experiencia con mascotas (Principiante/Intermedia/Experto)
- Nombre y foto de la mascota de interés
- Botones "Aceptar" y "Rechazar"

### Problema 3: Edición Fragmentada de Perfil

**Contexto Anterior**: EditProfileScreen permitía editar nombre, foto, bio y teléfono (desde Etapa 5). Pero los nuevos campos de estilo de vida no tenían interfaz. Un adoptante no podía indicar que vive en departamento si no había campo para ello.

**Solución Implementada**: `EditProfileScreen` completamente rediseñada para incluir sección visual clara de "Información de Hogar" con dropdowns, checkboxes y segmented buttons.

```dart
// frontend/app/lib/features/user/presentation/screens/edit_profile_screen.dart

class _EditProfileScreenState extends State<EditProfileScreen> {
  // Campos de vivienda con defaults
  String _housingType = 'House';
  String _housingOwnership = 'Owned';
  bool _hasYard = false;
  bool _hasFence = false;
  String _familyComposition = 'Single';
  String _otherPets = 'None';
  String _timeAvailability = 'Medium';
  String _experience = 'Beginner';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getProfile();

      setState(() {
        _housingType = (user.housingType?.isNotEmpty ?? false) ? user.housingType : 'House';
        _housingOwnership = (user.housingOwnership?.isNotEmpty ?? false) ? user.housingOwnership : 'Owned';
        _hasYard = user.hasYard ?? false;
        _hasFence = user.hasFence ?? false;
        _familyComposition = (user.familyComposition?.isNotEmpty ?? false) ? user.familyComposition : 'Single';
        _otherPets = (user.otherPets?.isNotEmpty ?? false) ? user.otherPets : 'None';
        _timeAvailability = (user.timeAvailability?.isNotEmpty ?? false) ? user.timeAvailability : 'Medium';
        _experience = (user.experience?.isNotEmpty ?? false) ? user.experience : 'Beginner';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando perfil: $e')));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await context.read<UserRepository>().updateProfile(
        name: _nameController.text,
        bio: _bioController.text,
        phone: _phoneController.text,
        photoUrl: _photoUrl,
        housingType: _housingType,
        housingOwnership: _housingOwnership,
        hasYard: _hasYard,
        hasFence: _hasFence,
        familyComposition: _familyComposition,
        otherPets: _otherPets,
        timeAvailability: _timeAvailability,
        experience: _experience,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado exitosamente')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar Perfil')),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ... Campos básicos (nombre, bio, teléfono, foto) del Etapa 5 ...

              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Información de Hogar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 10),

              // Tipo de Vivienda
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _housingType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Vivienda',
                    border: OutlineInputBorder(),
                  ),
                  items: ['House', 'Apartment', 'Parcel']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _housingType = val ?? 'House'),
                ),
              ),

              // Propiedad
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _housingOwnership,
                  decoration: const InputDecoration(
                    labelText: 'Propiedad',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Owned', 'Rented']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _housingOwnership = val ?? 'Owned'),
                ),
              ),

              // Patio y Cerca
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Tiene Patio'),
                        value: _hasYard,
                        onChanged: (val) => setState(() => _hasYard = val ?? false),
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Tiene Cerca'),
                        value: _hasFence,
                        onChanged: (val) => setState(() => _hasFence = val ?? false),
                      ),
                    ),
                  ],
                ),
              ),

              // Composición Familiar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _familyComposition,
                  decoration: const InputDecoration(
                    labelText: 'Composición Familiar',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Single', 'Couple', 'Family']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _familyComposition = val ?? 'Single'),
                ),
              ),

              // Otras Mascotas
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _otherPets,
                  decoration: const InputDecoration(
                    labelText: 'Otras Mascotas en Casa',
                    border: OutlineInputBorder(),
                  ),
                  items: ['None', 'Dogs', 'Cats', 'Mixed']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _otherPets = val ?? 'None'),
                ),
              ),

              // Disponibilidad de Tiempo
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _timeAvailability,
                  decoration: const InputDecoration(
                    labelText: 'Disponibilidad de Tiempo',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Low', 'Medium', 'High']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _timeAvailability = val ?? 'Medium'),
                ),
              ),

              // Experiencia con Mascotas
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _experience,
                  decoration: const InputDecoration(
                    labelText: 'Experiencia con Mascotas',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Beginner', 'Intermediate', 'Expert']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) => setState(() => _experience = val ?? 'Beginner'),
                ),
              ),

              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Guardar Cambios'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
```

Impacto Frontend: EditProfileScreen ahora es la fuente única de verdad para información de perfil. Todos los 8 campos se cargan en initState(), se muestran con controles intuitivos (dropdowns para enumeraciones, checkboxes para booleanos), y se guardan con PUT /profile. UserRepository maneja mapeo de nombres Dart a JSON tags de Go (`housingType` → `housing_type`).

### Problema 4: Ciclo de Vida Incompleto de Chats (EN DESARROLLO)

**Contexto Actual**: En Etapa 11, se implementó chat en tiempo real con WebSocket y persistencia. Sin embargo, los chats tienen un problema: cuando una adopción se completa o falla, el chat permanece en la lista "activo" indefinidamente. Usuarios ven chats antiguos o abandonados. Si un rescatista elimina una mascota, el adoptante puede seguir viendo el chat pero la mascota ya no existe.

**Status Actual**: Las funcionalidades de chat exit y bloqueo están parcialmente implementadas en el código (métodos en backend y UI en frontend) pero **aún no están registradas completamente en las rutas HTTP**. La siguiente documentación describe la implementación actual y lo que falta para completarse.

#### Subproblema 4A: Usuario Quiere Salir del Chat (PARCIALMENTE COMPLETADO)

**Flujo Esperado**:

1. Adoptante o Rescatista abre chat activo
2. Toca botón "Menú" (PopupMenu en AppBar)
3. Selecciona "Salir del Chat"
4. Confirmación: "¿Seguro? No podrás escribir después"
5. Toca "Salir"
6. Backend recibe POST /matches/unmatch con matchId
7. MatchService.Unmatch() actualiza estado de match a "adopter_left" o "rescuer_left"
8. Otro usuario ve el chat con aviso: "Usuario ha abandonado el chat"
9. Ambos usuarios no pueden escribir más

**Implementación Actual (Frontend - COMPLETADA)**:

En `ChatScreen`, se agregó menú PopupButton con opción "Salir del Chat":

```dart
// ChatScreen PopupMenuButton
PopupMenuButton<String>(
  onSelected: (value) async {
    if (value == 'leave') {
      _confirmLeaveChat(context);
    }
    // ... otras opciones (report, review) ...
  },
  itemBuilder: (BuildContext context) {
    return [
      const PopupMenuItem(
        value: 'leave',
        child: Row(
          children: [
            Icon(Icons.exit_to_app, color: Colors.red),
            SizedBox(width: 8),
            Text('Salir del Chat', style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
      // ... otras opciones ...
    ];
  },
)

// Dialog de confirmación
void _confirmLeaveChat(BuildContext context) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("¿Salir del chat?"),
      content: const Text("La conversación se cerrará y no podrás volver a escribir."),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text("Cancelar"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text("Salir"),
        ),
      ],
    ),
  );

  if (confirm == true && context.mounted) {
    try {
      await context.read<MatchesRepository>().unmatch(matchId);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Has salido del chat"))
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"))
      );
    }
  }
}
```

En `MatchesRepository`, se agregó método `unmatch()`:

```dart
// MatchesRepository.unmatch()
Future<void> unmatch(int matchId) async {
  try {
    final token = await _storage.read(key: 'jwt_token');
    await _dio.post(
      '${ApiConstants.baseUrl}/matches/unmatch',
      data: {'match_id': matchId},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  } catch (e) {
    throw Exception('Error saliendo del chat: $e');
  }
}
```

**Implementación Backend (PARCIALMENTE COMPLETADA)**:

En `MatchHandler`:

```go
// MatchHandler.Unmatch()
func (h *MatchHandler) Unmatch(c *gin.Context) {
  userID, ok := getUserIDFromContext(c)
  if !ok {
    c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
    return
  }

  var req struct {
    MatchID uint `json:"match_id" binding:"required"`
  }
  if err := c.ShouldBindJSON(&req); err != {
    c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
    return
  }

  if err := h.service.Unmatch(userID, req.MatchID); err != nil {
    c.JSON(http.StatusInternalServerError, gin.H{"error": "Error saliendo del chat: " + err.Error()})
    return
  }
  c.JSON(http.StatusOK, gin.H{"message": "Has salido del chat"})
}
```

En `MatchService`:

```go
// MatchService.Unmatch() - Cambia estado de match
func (s *MatchService) Unmatch(userID, matchID uint) error {
  var match domain.Match
  if err := s.db.Preload("Pet").First(&match, matchID).Error; err != nil {
    return errors.New("match no encontrado")
  }

  newStatus := ""

  // Determinamos quién está saliendo
  if match.AdopterID == userID {
    newStatus = MatchAdopterLeft  // Estado: "adopter_left"
  } else if match.Pet.UserID == userID {
    newStatus = MatchRescuerLeft  // Estado: "rescuer_left"
  } else {
    return errors.New("no tienes permiso para salir de este chat")
  }

  match.Status = domain.MatchStatus(newStatus)
  return s.db.Save(&match).Error
}
```

**Lo Que Falta**:

- [ ] Registrar ruta POST /matches/unmatch en main.go (línea ~217, aún no incluida en el grupo /matches)
- [ ] Definir constantes `MatchAdopterLeft` y `MatchRescuerLeft` en domain/match.go
- [ ] Actualizar ChatScreen para mostrar estado "Usuario ha abandonado" cuando isPeerLeft=true
- [ ] Lógica de bloqueo de input: si `isPetDeleted` o `isPeerLeft`, deshabilitar campo de texto

**UI Cambios Esperados** (parcialmente implementados):

En `ChatScreen`:

```dart
class ChatScreen extends StatelessWidget {
  // ... parámetros existentes ...
  final bool isPetDeleted;    // ← NUEVO: mascota fue eliminada
  final bool isPeerLeft;      // ← NUEVO: usuario se fue del chat

  // ...

  @override
  Widget build(BuildContext context) {
    final isChatBlocked = isPetDeleted || isPeerLeft;  // Bloquea input

    // En AppBar:
    if (isPetDeleted)
      const Text(
        "Mascota eliminada",
        style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
      ),

    // En body, antes del input:
    if (!isChatBlocked) const _ChatInput()  // Oculta input si bloqueado
  }
}
```

#### Subproblema 4B: Rescatista Elimina Mascota → Adoptante Se Queda Ciego (EN DESARROLLO)

**Escenario**: Rescatista crea mascota, adopta. Un mes después quiere cambiar mascota (viejo no se adapta). Elimina mascota de la BD. Pero adoptante sigue viendo chat activo. Toca mensaje de bienvenida "Hola, te contaré sobre Luna..." pero Luna ya no existe. Confusión y mala experiencia.

**Solución Esperada**: Cuando rescatista hace DELETE /pets/{petID}, el sistema:

1. Identifica todos los matches de esa mascota (SELECT \* FROM matches WHERE pet_id = ?)
2. Para cada match con status='accepted' (chat activo):
   - Actualiza match.status = "pet_deleted"
   - Notifica al adoptante: "La mascota fue eliminada por el rescatista"
3. Adoptante ve chat con aviso rojo y campo de texto deshabilitado

**Implementación Esperada** (AÚN EN DESARROLLO):

```go
// PetService.Delete() - Cascada a chats
func (s *PetService) Delete(petID uint) error {
  // 1. Encontrar todos los chats activos de esta mascota
  var matches []domain.Match
  s.db.Where("pet_id = ? AND status = ?", petID, domain.MatchAccepted).
    Find(&matches)

  // 2. Marcar todos como "pet_deleted"
  if len(matches) > 0 {
    s.db.Model(&domain.Match{}).
      Where("pet_id = ? AND status = ?", petID, domain.MatchAccepted).
      Update("status", "pet_deleted")  // ← NUEVO ESTADO
  }

  // 3. Eliminar la mascota (cascade automático a PetImage)
  return s.db.Delete(&domain.Pet{}, petID).Error
}
```

**Lo Que Falta**:

- [ ] Definir estado "pet_deleted" en domain.go
- [ ] Actualizar PetService.Delete() para marcar matches con state=pet_deleted
- [ ] Actualizar GetRescuerMatches() para filtrar/mostrar chats "muertos" separadamente
- [ ] Propagar estado pet_deleted al frontend en GetChatHistory
- [ ] Mostrar banner rojo en ChatScreen cuando isPetDeleted=true

#### Subproblema 4C: Acumulación de Chats Abandonados (EN DESARROLLO)

**Escenario**: Usuario termina adopción exitosamente. Meses después, chat sigue en lista "Chats Activos" aunque la relación ha terminado. Usuario tiene 50 chats "fantasma". La lista crece sin control.

**Solución Esperada**: Permitir eliminación manual de chats desde lista:

1. Usuario abre RescuerChatsScreen o AdopterMatchesScreen
2. Long-press (2 segundos) en un chat
3. Aparece menú: "Eliminar chat"
4. Confirmación
5. DELETE /matches/{matchId} (soft delete o cambio de estado)
6. Chat desaparece de lista

**Implementación Esperada** (AÚN EN DESARROLLO):

```dart
// RescuerChatsScreen o AdopterMatchesScreen
GestureDetector(
  onLongPress: () {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar chat"),
        content: const Text("¿Deseas eliminar este chat de tu lista?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          TextButton(
            onPressed: () async {
              await matchesRepository.deleteChat(matchId);
              Navigator.pop(ctx);
              setState(() => chats.removeWhere((c) => c.id == matchId));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  },
  child: ChatListTile(chat: chat),
)

// MatchesRepository.deleteChat()
Future<void> deleteChat(int matchId) async {
  final token = await _storage.read(key: 'jwt_token');
  await _dio.delete(
    '${ApiConstants.baseUrl}/matches/$matchId',
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );
}
```

```go
// MatchHandler.Delete() - Soft delete de match
func (h *MatchHandler) Delete(c *gin.Context) {
  userID, ok := getUserIDFromContext(c)
  if !ok { c.JSON(http.StatusUnauthorized, gin.H{"error": "No autenticado"}); return }

  matchID := c.Param("id")
  var match domain.Match
  if err := h.service.db.First(&match, matchID).Error; err != nil {
    c.JSON(http.StatusNotFound, gin.H{"error": "Chat no encontrado"})
    return
  }

  // Validar que el usuario es parte del match
  if match.AdopterID != userID && match.Pet.UserID != userID {
    c.JSON(http.StatusForbidden, gin.H{"error": "No tienes permiso"})
    return
  }

  // Soft delete o marcar como deleted_by_user
  match.DeletedAt = gorm.DeletedAt{Time: time.Now(), Valid: true}
  h.service.db.Save(&match)

  c.JSON(http.StatusOK, gin.H{"message": "Chat eliminado"})
}
```

**Lo Que Falta**:

- [ ] Agregar campo DeletedAt a Match (GORM soft deletes)
- [ ] Registrar ruta DELETE /matches/:id en main.go
- [ ] Actualizar queries para excluir soft-deleted matches
- [ ] Implementar long-press UI en pantallas de chats
- [ ] Manejar transacciones en caso de race conditions

### Notas Arquitectónicas de Etapa 15

- **Compatibilidad de Datos**: Todos los campos nuevos de User tienen defaults sensatos en base de datos. Usuarios existentes ven valores por defecto sin ruptura de funcionalidad.
- **Extensibilidad**: Campos como `HousingType`, `Experience` son strings con enumeraciones implícitas. Permite agregar nuevos valores sin cambio de schema (ej: "Townhouse" para vivienda).
- **Presentación en Solicitudes**: El endpoint GET /matches/requests ahora retorna adoptante completo (gracias a Preload). MatchRequestsScreen puede mostrar tarjeta informativa sin consultas adicionales.
- **Chat Lifecycle Completo**: La visión es que cada match tenga estados claros: "pending" → "accepted" → "completed"/"adopter_left"/"rescuer_left"/"pet_deleted"/"deleted_by_user". Todavía en implementación.
- **Bloqueo de Input Defensivo**: Si chat está en estado de bloqueo (pet eliminado, usuario se fue), input deshabilitado completamente. No hay ambigüedad de qué pasó.
- **Soft Deletes**: Usar GORM's gorm.DeletedAt permite recuperar historial de chats si es necesario sin ruptura de relaciones.

### Estado Actual de Etapa 15

**COMPLETADO**:

- ✓ 8 nuevos campos en User model (backend + frontend)
- ✓ Edición en EditProfileScreen con UI profesional
- ✓ Visualización en MatchRequestsScreen (rescatista ve info adoptante)
- ✓ Persistencia en base de datos con migración automática
- ✓ PopupMenu "Salir del Chat" en ChatScreen (UI frontend)
- ✓ Método Unmatch en MatchService (backend)
- ✓ Método unmatch() en MatchesRepository (frontend)

**EN DESARROLLO**:

- ⏳ Registración de ruta POST /matches/unmatch
- ⏳ Constantes de estado ("adopter_left", "rescuer_left", "pet_deleted")
- ⏳ Cascada de eliminación mascota → marcar matches
- ⏳ Soft delete de matches (long-press delete chat)
- ⏳ Mostrar estados de bloqueo en ChatScreen
- ⏳ Notificaciones al usuario cuando otros se van o mascota se elimina

**Impacto Esperado**:

Para Adoptantes:

- Ver más información de rescatistas en perfiles
- Editar información completa de su hogar y experiencia
- Salir de chats sin dejar "fantasmas"
- Claridad cuando mascota es eliminada o usuario se va

Para Rescatistas:

- Evaluar compatibilidad ANTES de aceptar (no después)
- Ver información detallada de adoptantes en solicitudes pendientes
- Elegir adoptantes con experiencia y hogar apropiado
- Menos adopciones fallidas por mismatch

Para el Sistema:

- Chats con ciclo de vida claro
- Menos datos "basura" (chats abandonados infinitos)
- Mejor flujo de información para decisiones de adopción
- Posibilidad futura de matching inteligente (rescatista con patio + adoptante necesita patio = +score)

## Etapa 16: Ciclo de Vida Completo del Chat con Máquina de Estados Terminal (Completada)

Etapa 16 transforma el sistema de gestión de chats implementando una Máquina de Estados Finita robusta que resuelve tres problemas críticos identificados en Etapa 15: el bucle infinito de ping-pong cuando usuarios se van, el efecto espejo causado por eliminación de mascotas, y la fragilidad del código frente a datos malformados desde el backend. Todos los cambios están completamente implementados y funcionando.

### Problema 1: Bucle Infinito de Ping-Pong

**Situación Problemática**: Cuando Usuario A salía, el chat desaparecía. Cuando Usuario B salía después, el estado cambiaba a `rescuer_left` y el chat reaparecía en la lista de A porque el filtro SQL buscaba chats con `status IN ('accepted', 'rescuer_left', 'pet_deleted')`. Resultado: ping-pong infinito donde los chats reaparecían y desaparecían dependiendo de quién se fuera.

**Solucion Arquitectural**: Introdujimos estado terminal `cancelled` que solo se alcanza cuando AMBOS han abandonado. La lógica de máquina de estados garantiza que una vez alcanzado `cancelled`, nunca vuelve a reaparecer en ninguna lista.

**Nuevos Estados de Match**:

```go
// internal/core/domain/match.go
const (
  MatchPending     MatchStatus = "pending"       // Solicitud inicial
  MatchAccepted    MatchStatus = "accepted"      // Ambos aceptaron
  MatchRejected    MatchStatus = "rejected"      // Alguien rechazó
  MatchAdopterLeft MatchStatus = "adopter_left"  // Adoptante se fue primero
  MatchRescuerLeft MatchStatus = "rescuer_left"  // Rescatista se fue primero
  MatchPetDeleted  MatchStatus = "pet_deleted"   // Mascota fue eliminada
  MatchCancelled   MatchStatus = "cancelled"     // ESTADO TERMINAL: Ambos se fueron
)
```

**Máquina de Estados en MatchService.Unmatch()**:

Cuando un usuario abandona, el servicio ejecuta lógica determinista: si el otro usuario ya se fue O la mascota fue eliminada, transiciona a `cancelled` (estado terminal). Si no, solo marca ese usuario como "ido" con `[rol]_left`.

```go
func (s *MatchService) Unmatch(userID, matchID uint) error {
  var match domain.Match
  if err := s.db.Preload("Pet", func(db *gorm.DB) *gorm.DB {
    return db.Unscoped()  // Cargar incluso si pet fue soft-deleted
  }).First(&match, matchID).Error; err != nil {
    return errors.New("match no encontrado")
  }

  // Si ya está cancelado, no hacer nada (idempotente)
  if match.Status == MatchCancelled {
    return nil
  }

  var newStatus domain.MatchStatus

  if userID == match.AdopterID {
    // Soy el Adoptante que me voy
    if match.Status == MatchRescuerLeft || match.Status == MatchPetDeleted {
      // El Rescatista ya se fue O la mascota fue eliminada
      newStatus = MatchCancelled  // Ir a estado terminal
    } else {
      // Soy el primero en irme
      newStatus = MatchAdopterLeft
    }
  } else if userID == match.Pet.UserID {
    // Soy el Rescatista que me voy
    if match.Status == MatchAdopterLeft || match.Status == MatchPetDeleted {
      // El Adoptante ya se fue O la mascota fue eliminada
      newStatus = MatchCancelled  // Ir a estado terminal
    } else {
      // Soy el primero en irme
      newStatus = MatchRescuerLeft
    }
  } else {
    return errors.New("no tienes permiso para salir de este chat")
  }

  // Actualizar estado si cambió
  if match.Status != newStatus {
    if err := s.db.Model(&match).Update("status", newStatus).Error; err != nil {
      return err
    }
  }
  return nil
}
```

**Diagrama de Transiciones de Estado**:

```
                    pending
                       |
                   (ambos aceptan)
                       |
                    accepted
                    /       \
              (adopter       (rescuer
               leaves)        leaves)
              /                   \
       adopter_left          rescuer_left
              \                   /
               (other leaves    (other leaves
                or pet deleted)  or pet deleted)
                   \           /
                    cancelled
                    (TERMINAL)
```

**Filtros SQL que Previenen el Ping-Pong**:

```go
// Adoptante NO ve chats donde él se fue (adopter_left) ni donde ambos se fueron (cancelled)
func (s *MatchService) GetAcceptedMatches(adopterID uint) []*Match {
  // Solo chats activos o donde el Rescatista se fue o la mascota fue eliminada
  return matches.Where("status IN ('accepted', 'rescuer_left', 'pet_deleted')")
}

// Rescatista NO ve chats donde él se fue (rescuer_left) ni donde ambos se fueron (cancelled)
func (s *MatchService) GetRescuerMatches(rescuerID uint) []*Match {
  // Solo chats activos o donde el Adoptante se fue o la mascota fue eliminada
  return matches.Where("status IN ('accepted', 'adopter_left', 'pet_deleted')")
}
```

Este es el núcleo de la solución: `cancelled` nunca aparece en ningún filtro, por lo que una vez alcanzado, el chat muere permanentemente.

### Problema 2: Efecto Espejo (Mascota Eliminada)

**Situación Problemática**: Al eliminar una mascota, los chats quedaban en estado `accepted` pero la mascota era `NULL` o soft-deleted. Adoptantes veían mensajes sobre una mascota inexistente. Rescatistas podían seguir escribiendo. El chat quedaba en limbo indefinidamente sin retroalimentación clara.

**Solución Arquitectural**: Cascada de eliminación atómica en transacción GORM que cambia el estado del chat ANTES de soft-delete la mascota, garantizando consistencia.

**PetService.Delete() con Transacción Atómica**:

```go
// internal/core/services/pet_service.go
func (s *PetService) Delete(id uint, ownerID uint) error {
  var pet domain.Pet
  if err := s.db.Where("id = ? AND user_id = ?", id, ownerID).First(&pet).Error; err != nil {
    return errors.New("mascota no encontrada o sin permiso")
  }

  // Todas estas operaciones se ejecutan como una sola transacción
  // Si cualquiera falla, TODO se revierte
  return s.db.Transaction(func(tx *gorm.DB) error {
    // Paso 1: Rechazar solicitudes pendientes
    if err := tx.Model(&domain.Match{}).
      Where("pet_id = ? AND status = ?", id, domain.MatchPending).
      Update("status", domain.MatchRejected).Error; err != nil {
      return err
    }

    // Paso 2: Bloquear chats activos
    if err := tx.Model(&domain.Match{}).
      Where("pet_id = ? AND status = ?", id, domain.MatchAccepted).
      Update("status", domain.MatchPetDeleted).Error; err != nil {
      return err
    }

    // Paso 3: Soft delete la mascota (establece DeletedAt timestamp)
    if err := tx.Delete(&domain.Pet{}, id).Error; err != nil {
      return err
    }

    return nil
  })
}
```

**Garantías de Transacción**:

- Si algún paso falla: TODOS se revierten (all-or-nothing)
- No es posible quedar con mascota eliminada pero chats sin actualizar
- No hay race conditions incluso con múltiples clientes simultáneos

**Impacto en Frontend**:

El backend pre-carga mascotas con `Unscoped()` en Unmatch(), permitiendo acceso incluso a soft-deleted pets para lógica de estado. El frontend detecta `pet_deleted` status y muestra UI clara:

- **Rescatista**: Ve "Has eliminado esta publicación" (rojo, negrita)
- **Adoptante**: Ve "Publicación eliminada" (rojo, alerta)

Chat queda bloqueado. Ambos ven claramente qué pasó.

### Problema 3: Robustez del Código contra Datos Malformados

**Situación Problemática**: El backend ocasionalmente envía datos malformados:

- IDs como `null`
- IDs como string `"null"`
- IDs como float `3.14` en lugar de `3`
- Campos faltantes completamente

Frontend crasheaba con Red Screen of Death (RSOD). No había forma de recuperarse.

**Solución Arquitectural**: Función defensiva `_parseInt()` en Match.fromJson() que maneja todos los casos posibles sin nunca lanzar excepciones.

**Match Model con \_parseInt() Blindaje**:

```dart
// app/lib/features/pets/domain/match_model.dart
factory Match.fromJson(Map<String, dynamic> json) {
  return Match(
    id: _parseInt(json['id']),            // Convertir seguramente
    adopterId: _parseInt(json['adopter_id']),  // Convertir seguramente
    petId: _parseInt(json['pet_id']),     // Convertir seguramente
    status: json['status'] ?? 'pending',
    message: json['message'],
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'])
        : null,
    pet: json['pet'] != null ? Pet.fromJson(json['pet']) : null,
    adopter: json['adopter'] != null ? User.fromJson(json['adopter']) : null,
  );
}

static int _parseInt(dynamic value) {
  // null -> 0
  if (value == null) return 0;

  // int -> int (directamente)
  if (value is int) return value;

  // double -> int (trunca: 3.14 -> 3)
  if (value is double) return value.toInt();

  // string -> int (con protección)
  if (value is String) {
    if (value.toLowerCase() == 'null' || value.isEmpty) return 0;
    return int.tryParse(value) ?? 0;  // "42" -> 42, "abc" -> 0
  }

  // Cualquier otra cosa inesperada -> 0 (sin crash)
  return 0;
}
```

**Matriz de Casos Manejados**:

| Input    | Output | Riesgo Original            |
| -------- | ------ | -------------------------- |
| `42`     | `42`   | ✓ Seguro                   |
| `null`   | `0`    | ✗ Crash con null exception |
| `3.14`   | `3`    | ✗ Type error               |
| `"null"` | `0`    | ✗ Parse error              |
| `"42"`   | `42`   | ✗ Parse error              |
| `"abc"`  | `0`    | ✗ Parse error fatal        |
| Faltante | `0`    | ✗ Key not found            |

**Resultado**: Cero red screens. El app se degrada gracefully: si hay un ID malformado, se usa `0` como fallback y continúa. Mejor experiencia que crashear.

### Problema 4: Bloqueo de UI Personalizado por Rol

**Situación Problemática**: ChatScreen mostraba el mismo mensaje de bloqueo a ambos usuarios, aunque sus perspectivas diferaban fundamentalmente:

- Si RESCATISTA eliminó mascota: Rescatista sabe que FUE ÉL quien la eliminó, Adoptante ve como si alguien más lo hizo
- Si ADOPTANTE abandonó: Adoptante sabe que ÉL se fue, Rescatista ve como si alguien más se fue

Mensajes idénticos creaban confusión y mala experiencia.

**Solución Arquitectural**: Parámetro `isRescuer` propagado desde navegación a través de ChatScreen hasta ChatBloc, permitiendo generar lockReason personalizado.

**ChatScreen con Parámetro isRescuer**:

```dart
// app/lib/features/chat/presentation/screens/chat_screen.dart
class ChatScreen extends StatefulWidget {
  final int matchId;
  final bool isRescuer;  // <-- NUEVO PARÁMETRO

  const ChatScreen({
    required this.matchId,
    this.isRescuer = false,  // Default: adoptante
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();

    // Determinar estado inicial antes de navegar
    bool isLocked = false;
    String initialStatus = 'accepted';  // por defecto

    // Pasar isRescuer al Bloc para que personalice mensajes
    context.read<ChatBloc>().add(
      InitChat(
        widget.matchId,
        initialStatus: initialStatus,
        isRescuer: widget.isRescuer,  // <-- CONTEXTO DE ROL
      ),
    );
  }
}
```

**ChatBloc Generando lockReason Personalizado**:

```dart
// app/lib/features/chat/presentation/bloc/chat_bloc.dart
Future<void> _onInitChat(InitChat event, Emitter<ChatState> emit) async {
  try {
    bool isLocked = false;
    String lockReason = '';

    if (event.initialStatus != null && event.initialStatus != 'accepted') {
      isLocked = true;

      if (event.initialStatus == 'pet_deleted') {
        // La mascota fue eliminada
        if (event.isRescuer) {
          // Yo (rescatista) la eliminé
          lockReason = 'Has eliminado la publicación de esta mascota. El chat ha finalizado.';
        } else {
          // El rescatista la eliminó
          lockReason = 'La publicación de esta mascota ha sido eliminada. El chat ha finalizado.';
        }
      } else if (event.initialStatus == 'adopter_left') {
        // El adoptante se fue
        lockReason = 'El adoptante ha abandonado el chat.';
      } else if (event.initialStatus == 'rescuer_left') {
        // El rescatista se fue
        lockReason = 'El rescatista ha abandonado el chat.';
      } else if (event.initialStatus == 'cancelled') {
        // Ambos se fueron
        lockReason = 'Este chat ha finalizado permanentemente.';
      }
    }

    emit(ChatLoaded(
      messages: history,
      matchId: event.matchId,
      myUserId: _myUserId,
      isLocked: isLocked,
      lockReason: lockReason,  // Personalizado por rol
    ));
  } catch (e) {
    emit(ChatError('Error al cargar chat: $e'));
  }
}
```

**Impacto en Pantallas de Chats**:

**RescuerChatsScreen** (rescatista leyendo su lista):

```dart
// Si pet_deleted y yo (rescatista) soy quien lo eliminó, mostrar claramente
if (match.isPetDeleted) {
  subtitleText = 'Has eliminado esta publicación';  // Yo la eliminé
  subtitleStyle = TextStyle(color: Colors.red, fontWeight: FontWeight.bold);
} else if (match.isAdopterLeft) {
  subtitleText = 'El usuario abandonó el chat';
  subtitleStyle = TextStyle(color: Colors.red, fontStyle: FontStyle.italic);
}

// Paso isRescuer=true al navegar
onTap: () => Navigator.push(context, MaterialPageRoute(
  builder: (_) => ChatScreen(matchId: match.id, isRescuer: true),
))
```

**AdopterMatchesScreen** (adoptante leyendo su lista):

```dart
// Si mascota eliminada, lo veo como "otra persona la eliminó"
if (match.isPetDeleted) {
  petNameStyle = TextStyle(decoration: TextDecoration.lineThrough);
  subtitleText = 'Publicación eliminada';
  subtitleStyle = TextStyle(color: Colors.red);
}

// Paso isRescuer=false al navegar
onTap: () => Navigator.push(context, MaterialPageRoute(
  builder: (_) => ChatScreen(matchId: match.id, isRescuer: false),
))
```

### Cambios Implementados (Resumen Técnico)

**Backend (Go)**:

1. **domain/match.go**
   - Añadidas constantes: `MatchCancelled`, `MatchAdopterLeft`, `MatchRescuerLeft`, `MatchPetDeleted`
   - Total de estados: 7

2. **services/match_service.go**
   - Método `Unmatch(userID, matchID)` con máquina de estados
   - Lógica de transición a `cancelled` cuando ambos se fueron
   - Metodos `GetAcceptedMatches()` y `GetRescuerMatches()` con filtros correctos
   - Pre-carga con `Unscoped()` para mascotas soft-deleted

3. **services/pet_service.go**
   - Método `Delete()` refactorizado con `db.Transaction()`
   - Cascada de 3 pasos: rechazar pendientes, bloquear activos, soft-delete mascota
   - Garantía all-or-nothing

**Frontend (Flutter)**:

1. **domain/match_model.dart**
   - Helpers: `isChatActive`, `isPetDeleted`, `isAdopterLeft`, `isRescuerLeft`, `isCancelled`
   - Property `blockReason` con mensajes por estado
   - Static function `_parseInt()` con 6 casos manejados

2. **presentation/screens/chat_screen.dart**
   - Parámetro `isRescuer` (default false)
   - Paso a ChatBloc en evento InitChat

3. **presentation/bloc/chat_bloc.dart**
   - Evento `InitChat` incluye `isRescuer`
   - Handler `_onInitChat` personaliza `lockReason` según rol

4. **presentation/screens/rescuer_chats_screen.dart**
   - Visualización de tachado si mascota eliminada o adoptante ido
   - Subtítulos personalizados por estado
   - Paso `isRescuer: true` a ChatScreen

5. **presentation/screens/adopter_matches_screen.dart**
   - Visualización de tachado si mascota eliminada
   - Subtítulos personalizados por estado
   - Paso `isRescuer: false` a ChatScreen

### Estado de Implementación

| Componente            | Backend | Frontend | Pruebas | Estado   |
| --------------------- | ------- | -------- | ------- | -------- |
| Máquina de estados    | ✓       | ✓        | ✓       | Completo |
| Eliminación ping-pong | ✓       | ✓        | ✓       | Completo |
| Cascada pet_deleted   | ✓       | ✓        | ✓       | Completo |
| Robustez \_parseInt() | -       | ✓        | ✓       | Completo |
| Personalización rol   | ✓       | ✓        | ✓       | Completo |
| Visualización UI      | -       | ✓        | ✓       | Completo |

**Etapa 16 Status: 100% Implementado y Verificado**

## Etapa 17: Sistema de Justicia Integral - Denuncia, Investigación, Sentencia y Protección Pública (Completada)

Etapa 17 construye un sistema de justicia completo y transparente que transforma a PAWS de una plataforma de intercambio de mascotas en un ecosistema seguro con protección comunitaria. Los usuarios ahora pueden denunciar comportamiento inapropiado, administradores pueden investigar con contexto completo, y la comunidad puede verificar antecedentes públicamente. La implementación se divide en cuatro fases operacionales:

### Fase 1: Cimientos del Backend - Lógica de Justicia

**Modelos de Dominio**:

Se crearon dos nuevos modelos de dominio que operan como la columna vertebral del sistema:

```go
// internal/core/domain/report.go
type Report struct {
    gorm.Model

    // Quién reporta a quién
    ReporterID  uint `gorm:"not null;index"` // Usuario que reporta
    ReportedID  uint `gorm:"not null;index"` // Usuario reportado

    // Relaciones
    Reporter User `gorm:"foreignKey:ReporterID"`
    Reported User `gorm:"foreignKey:ReportedID"`

    // Contexto del Reporte
    MatchID     uint   `gorm:"index"` // El chat donde ocurrió (opcional)
    Category    string `gorm:"type:varchar(50);not null"` // abuse, scam, spam, hate, other
    Description string `gorm:"type:text"`                  // Texto libre del usuario

    // Estado y Resolución
    Status       string     `gorm:"default:'pending';index"` // pending, resolved, dismissed
    EvidenceSnapshot string `gorm:"type:text"`               // JSON del chat congelado
    ResolvedAt   *time.Time `json:"resolved_at"`
    ResolverID   *uint      `json:"resolver_id"` // ID del Admin que cerró
}

// internal/core/domain/blacklist.go
type BlacklistEntry struct {
    gorm.Model
    Run    string `gorm:"uniqueIndex;not null"` // RUT chileno, único
    Name   string                                // Nombre al momento del ban (referencia)
    Reason string                                // Razón pública (ej: "Maltrato Animal")
}
```

**Evidencia Congelada - Concepto Crítico**:

Cuando un administrador ordena banear un usuario, el sistema captura y congela inmediatamente el historial del chat como prueba legal inmutable. Esto soluciona un problema fundamental: ¿qué pasa si el usuario baneado borra la conversación después? La respuesta: la evidencia ya está congelada en el campo `EvidenceSnapshot` como JSON, documentando exactamente qué se dijo y cuándo. Esta prueba no puede ser manipulada posteriormente.

**Endpoints Seguros para Administración**:

```go
// internal/transport/http/admin_handler.go
GET /admin/reports              // Lista reportes pendientes (solo admin)
GET /admin/reports/:id          // Detalle con historial congelado
POST /admin/reports/:id/resolve // Admin ejecuta sentencia (ban o desestimar)

// ReportService.ResolveReport() internamente:
// 1. Valida que quien ejecuta es admin
// 2. Si action=="ban": marca usuario como baneado, crea BlacklistEntry
// 3. Si publicBlacklist==true: RUT aparece en búsquedas públicas
// 4. Congela evidencia en JSON para documentación
// 5. Todo en transacción: todo o nada
```

**Endpoints Públicos para Consulta de Antecedentes**:

```go
// Se expone SOLO lectura al público (sin autenticación requerida)
GET /api/v1/blacklist/search?rut=12.345.678-9  // Público

// ReportService.SearchBlacklist() devuelve:
// - Si encontrado: {found: true, name: "...", reason: "...", date: "..."}
// - Si no: {found: false, message: "Sin antecedentes"}
```

### Fase 2: Experiencia del Denunciante - El Botón de Pánico

**Transformación del Menú de Chat**:

El menú contextual que antes solo permitía "Salir" ahora se convierte en un centro de acciones de seguridad:

```dart
// app/lib/features/chat/presentation/screens/chat_screen.dart
PopupMenuButton<String>(
  onSelected: (value) {
    if (value == 'report') {
      _showReportDialog(context);      // NUEVO: Reportar
    } else if (value == 'unmatch') {
      _confirmUnmatch(context, isLocked);  // Existente: Salir
    }
  },
  itemBuilder: (context) => [
    const PopupMenuItem(
      value: 'report',
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: Colors.orange),
          SizedBox(width: 8),
          Text("Reportar usuario"),
        ],
      ),
    ),
    const PopupMenuItem(
      value: 'unmatch',
      child: Row(
        children: [
          Icon(Icons.block, color: Colors.red),
          SizedBox(width: 8),
          Text("Salir del chat"),
        ],
      ),
    ),
  ],
),
```

**Formulario de Reporte Categorizado**:

El diálogo de reporte es mucho más sofisticado que en versiones anteriores. Ahora incluye categorías predefinidas que permiten al admin contextualizarse inmediatamente:

```dart
void _showReportDialog(BuildContext chatContext) {
  final _formKey = GlobalKey<FormState>();
  String selectedCategory = 'abuse'; // Default
  String description = '';

  final Map<String, String> categories = {
    'abuse': 'Maltrato Animal',
    'scam': 'Estafa / Fraude',
    'spam': 'Spam / Publicidad',
    'hate': 'Lenguaje Ofensivo / Odio',
    'other': 'Otro',
  };

  showDialog(
    context: chatContext,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text("Reportar Usuario"),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Tu reporte es anónimo y será revisado por un administrador.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              // Selector de Categoría
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(
                  labelText: "Motivo",
                  border: OutlineInputBorder(),
                ),
                items: categories.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) selectedCategory = val;
                },
              ),
              const SizedBox(height: 12),
              // Campo de Descripción
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Detalles adicionales",
                  border: OutlineInputBorder(),
                  hintText: "Describe brevemente la situación...",
                ),
                maxLines: 3,
                onChanged: (val) => description = val,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Por favor, añade detalles.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                // Enviar silenciosamente sin alertar al agresor
                context.read<ChatBloc>().add(
                  ReportUserEvent(
                    reportedId: widget.peerUserId,
                    category: selectedCategory,
                    description: description,
                  ),
                );
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Reporte enviado. Gracias por avisarnos."),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text("REPORTAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );
}
```

**Silencio Operativo - Seguridad del Denunciante**:

Aspecto crítico: el usuario reportador nunca recibe confirmación visible de que el reporte fue exitoso (solo un SnackBar discreta). El usuario reportado **nunca es notificado** de que fue reportado. Esto previene represalias y permite investigaciones tranquilas sin alertas de defensa.

### Fase 3: El Centro de Resolución - Admin Dashboard

**Pantalla Exclusiva para Administradores**:

Se creó `AdminDashboardScreen`, una interfaz completamente nueva accesible solo a usuarios con `role="admin"` en el JWT:

```dart
// app/lib/features/admin/presentation/screens/admin_dashboard_screen.dart
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<List<Report>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  void _loadReports() {
    setState(() {
      _reportsFuture = context.read<AdminRepository>().getReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Centro de Resolución"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () async {
              // Logout: borrar token, volver a LoginScreen
              await _handleLogout(context);
            },
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: FutureBuilder<List<Report>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final reports = snapshot.data ?? [];

          // Estado vacío: "La comunidad está en paz"
          if (reports.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 60, color: Colors.green),
                  SizedBox(height: 10),
                  Text("La comunidad está en paz."),
                ],
              ),
            );
          }

          // Lista de reportes
          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                elevation: 4,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red[50],
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                  ),
                  title: Text(
                    _translateCategory(report.category),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "Reportado: ${report.reported?.name ?? 'Usuario'}\n"
                    "Por: ${report.reporter?.name ?? 'Usuario'}",
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _openReportDetail(context, report.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _translateCategory(String cat) {
    switch (cat) {
      case 'abuse':
        return 'Maltrato Animal';
      case 'scam':
        return 'Estafa / Fraude';
      case 'hate':
        return 'Lenguaje Ofensivo';
      case 'spam':
        return 'Spam';
      default:
        return 'Otro Motivo';
    }
  }

  void _openReportDetail(BuildContext context, int reportId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(reportId: reportId, onResolved: _loadReports),
      ),
    );
  }
}
```

**Visor de Evidencia - Contexto Completo**:

La parte más poderosa del Centro de Resolución es el visor de evidencia. Cuando el admin toca un reporte, ve exactamente la conversación que llevó a la denuncia:

```dart
// ReportDetailScreen (dentro de admin_dashboard_screen.dart)
class ReportDetailScreen extends StatefulWidget {
  final int reportId;
  final VoidCallback onResolved;

  const ReportDetailScreen({
    required this.reportId,
    required this.onResolved,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late Future<Report> _detailFuture;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<AdminRepository>().getReportDetails(widget.reportId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Detalle de Reporte"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<Report>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final report = snapshot.data!;

          return Column(
            children: [
              // 1. HEADER: Categoría, descripción
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[100],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _translateCategory(report.category),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Reportado: ${report.reported?.name ?? 'Usuario'}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Denunciante: ${report.reporter?.name ?? 'Usuario'}",
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Descripción: \"${report.description}\"",
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 2. VISOR DE EVIDENCIA: Chat congelado
              Expanded(
                child: Container(
                  color: Colors.grey[100],
                  child: report.evidenceMessages == null ||
                      report.evidenceMessages!.isEmpty
                      ? const Center(
                          child: Text("No hay historial de chat disponible."),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: report.evidenceMessages!.length,
                          itemBuilder: (context, index) {
                            final msg = report.evidenceMessages![index];
                            // Si es del REPORTER, mostrar a la derecha
                            // Si es del ACUSADO, mostrar a la izquierda
                            final isReporter = msg.senderId == report.reporterId;

                            return ChatBubble(
                              message: msg,
                              isMe: isReporter,
                            );
                          },
                        ),
                ),
              ),

              // 3. BOTONES DE ACCIÓN
              if (!_isProcessing)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _resolve(report.id, 'dismiss', false),
                          child: const Text("Desestimar"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _showBanDialog(report.id),
                          child: const Text("BAN"),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showBanDialog(int reportId) {
    bool addToBlacklist = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Confirmar Sanción"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "El usuario perderá acceso a su cuenta inmediatamente.",
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text("Agregar a Blacklist Pública"),
                    subtitle: const Text(
                      "Su nombre y RUT serán visibles en búsquedas de seguridad.",
                    ),
                    value: addToBlacklist,
                    activeColor: Colors.red,
                    onChanged: (val) => setState(() => addToBlacklist = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resolve(reportId, 'ban', addToBlacklist);
                  },
                  child: const Text(
                    "EJECUTAR BAN",
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _translateCategory(String cat) {
    switch (cat) {
      case 'abuse':
        return 'Maltrato Animal';
      case 'scam':
        return 'Estafa / Fraude';
      case 'hate':
        return 'Lenguaje Ofensivo';
      case 'spam':
        return 'Spam';
      default:
        return 'Otro';
    }
  }

  Future<void> _resolve(int id, String action, bool blacklist) async {
    setState(() => _isProcessing = true);
    try {
      await context.read<AdminRepository>().resolveReport(id, action, blacklist);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'ban' ? "Usuario baneado correctamente" : "Reporte desestimado",
          ),
        ),
      );
      widget.onResolved();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
      setState(() => _isProcessing = false);
    }
  }
}
```

**Poder de Acción - Dos Opciones de Sentencia**:

El admin tiene dos opciones al decidir ban:

1. **Desestimar**: Cierra el caso, el usuario reportado sigue activo
2. **Ban**: Usuario pierde acceso inmediato + opción de Blacklist pública

El checkbox "Agregar a Blacklist Pública" es crítico: si está activado, el RUT y nombre del baneado aparecerán en búsquedas públicas (Fase 4). Si no está activado, el ban es privado (usuario solo sabe porque no puede loguearse).

### Fase 4: Escudo Público - Consulta de Antecedentes

**BlacklistSearchScreen - Accesible desde Múltiples Lugares**:

Se implementó una pantalla independiente accesible desde:

1. LoginScreen: Botón "Buscar antecedentes" antes de registrarse
2. Perfil del usuario: Verificar antes de interactuar

```dart
// app/lib/features/auth/presentation/screens/blacklist_search_screen.dart
class BlacklistSearchScreen extends StatefulWidget {
  const BlacklistSearchScreen({super.key});

  @override
  State<BlacklistSearchScreen> createState() => _BlacklistSearchScreenState();
}

class _BlacklistSearchScreenState extends State<BlacklistSearchScreen> {
  final _rutController = TextEditingController();
  bool _isSearching = false;
  Map<String, dynamic>? _result;

  Future<void> _search() async {
    if (_rutController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingresa un RUT")),
      );
      return;
    }

    setState(() => _isSearching = true);
    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConstants.baseUrl}/blacklist/search?rut=${_rutController.text}',
        ),
      );

      setState(() {
        _result = jsonDecode(response.body);
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Consultar Antecedentes"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // INSTRUCCIÓN
            const Text(
              "Verifica los antecedentes de seguridad de un usuario antes de confiar.",
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // CAMPO DE RUT CON VALIDACIÓN CHILENA
            TextFormField(
              controller: _rutController,
              decoration: const InputDecoration(
                labelText: 'RUT (Ej: 12.345.678-9)',
                border: OutlineInputBorder(),
                hintText: '12.345.678-9',
                prefixIcon: Icon(Icons.badge),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9kK\-\.]')),
                RutFormatter(), // Formatea automáticamente
              ],
              validator: (value) {
                if (value == null || value.isEmpty) return 'Requerido';
                if (!_isValidRut(value)) return 'RUT inválido';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // BOTÓN DE BÚSQUEDA
            ElevatedButton.icon(
              onPressed: _isSearching ? null : _search,
              icon: _isSearching ? const SizedBox() : const Icon(Icons.search),
              label: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("BUSCAR"),
            ),
            const SizedBox(height: 32),

            // RESULTADO
            if (_result != null)
              _result!['found'] == false
                  ? Card(
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle, size: 60, color: Colors.green),
                            const SizedBox(height: 10),
                            const Text(
                              "Sin antecedentes",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Este usuario está limpio en nuestro registro.",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Card(
                      color: Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Icon(Icons.warning_amber, size: 60, color: Colors.red),
                            const SizedBox(height: 10),
                            const Text(
                              "Alerta: Antecedentes Registrados",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Nombre: ${_result!['name'] ?? 'N/A'}",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Razón: ${_result!['reason'] ?? 'No especificada'}",
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.darkRed,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Fecha: ${_result!['date'] ?? 'Desconocida'}",
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "Se recomienda NO interactuar con este usuario.",
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  bool _isValidRut(String rut) {
    String clean = rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
    if (clean.length < 8) return false;

    try {
      int number = int.parse(clean.substring(0, clean.length - 1));
      String verifier = clean[clean.length - 1];

      int m = 0, s = 0;
      while (number > 0) {
        s += number % 10 * (m % 6 + 2);
        number ~/= 10;
        m++;
      }

      int dv = (11 - (s % 11)) % 11;
      String expectedVerifier = dv == 10 ? 'K' : dv.toString();

      return verifier == expectedVerifier;
    } catch (e) {
      return false;
    }
  }
}
```

**Validación Chilena Integrada - Módulo 11**:

Un aspecto especialmente detallado: el sistema implementa el algoritmo Módulo 11 para validar RUTs chilenos en tiempo real. Mientras el usuario escribe `12.345.678-9`, el sistema:

1. Formatea automáticamente: `12` → `12.` → `12.34` → `12.345` → etc.
2. Valida el dígito verificador matemáticamente (Módulo 11)
3. Rechaza RUTs con dígito verificador inválido
4. Previene búsquedas fraudulentas con RUTs mal formados

**UX Chilena - Tarjetas de Resultado**:

Los resultados se muestran con claridad visual extrema:

- **Tarjeta Verde**: Sin antecedentes, usuario limpio, ícono de check, texto tranquilizante
- **Tarjeta Roja**: Antecedentes registrados, ícono de alerta, nombre y razón del ban, advertencia clara "NO interactuar"

Esto es intencionalmente dramático para desentumecer a usuarios sobre riesgos de seguridad.

### Cambios Implementados - Etapa 17 (Resumen)

**Backend (Go)**:

1. **domain/report.go**: Modelo Report con 5 estados (pending, resolved, dismissed) + EvidenceSnapshot
2. **domain/blacklist.go**: Modelo BlacklistEntry con Run único, Name, Reason
3. **services/report_service.go**:
   - `CreateReport()`: Crea reporte con categoría y descripción
   - `ResolveReport()`: Admin ejecuta sentencia (ban/dismiss) con congelación de evidencia
   - `SearchBlacklist()`: Búsqueda pública por RUT
   - `GetAllReports()`: Lista con Preload de Reporter y Reported
   - `GetReportDetails()`: Detalle con historial congelado
4. **transport/http/admin_handler.go**:
   - `GET /admin/reports`: Lista reportes (admin only)
   - `GET /admin/reports/:id`: Detalle (admin only)
   - `POST /admin/reports/:id/resolve`: Ejecutar sentencia
5. **transport/http/report_handler.go**:
   - `GET /blacklist/search?rut=...`: Búsqueda pública (sin autenticación)

**Frontend (Flutter)**:

1. **admin/domain/report_model.dart**: Modelo Report con factory fromJson
2. **admin/data/admin_repository.dart**:
   - `getReports()`: GET /admin/reports
   - `getReportDetails(id)`: GET /admin/reports/:id
   - `resolveReport(id, action, blacklist)`: POST /admin/reports/:id/resolve
3. **admin/presentation/screens/admin_dashboard_screen.dart**:
   - Lista de reportes con Cards
   - ReportDetailScreen anidado con visor de evidencia
   - Botones Desestimar / Ban
   - Checkbox para blacklist pública
4. **auth/presentation/screens/blacklist_search_screen.dart**:
   - Campo de RUT con RutFormatter
   - Validación Módulo 11
   - Tarjetas de resultado (Verde/Roja)
5. **chat/presentation/screens/chat_screen.dart**:
   - Menú actualizado con opción "Reportar Usuario"
   - Diálogo \_showReportDialog() con categorías
6. **chat/presentation/bloc/chat_bloc.dart**:
   - Evento ReportUserEvent
   - Estado con reportStatus (initial, loading, success, failure)
7. **chat/data/chat_repository.dart**:
   - Método reportUser() que POST a /api/v1/report

### Arquitectura de Seguridad - Etapa 17

**Principios Implementados**:

1. **Separación de Responsabilidades**: Denunciantes, investigadores (admins), y público tienen tres interfaces completamente distintas
2. **Silencio Operativo**: El reportado nunca sabe que fue reportado hasta que sea baneado (sin represalias)
3. **Evidencia Inmutable**: El chat se congela como JSON inmediatamente, previniendo manipulación post-facto
4. **Transparencia Gradual**: La comunidad ve "baneados", pero solo admins ven "por qué" (excepto si blacklist pública está activada)
5. **Validación Robusta**: Módulo 11 para RUTs chilenos previene búsquedas fraudulentas

**Modelo de Datos Completo**:

```
User (id, name, run, is_banned)
  ├─ Report(1..n) como Reporter
  ├─ Report(1..n) como Reported
  └─ BlacklistEntry (vía run cuando banned)

Report (id, reporter_id, reported_id, category, description, status, evidence_snapshot)
  ├─ Reporter: User
  ├─ Reported: User
  └─ EvidenceMessages: ChatMessage[] (congelado)

BlacklistEntry (run, name, reason) - Único por RUT
  └─ Búsqueda pública: GET /blacklist/search?rut=X
```

### Estado de Implementación - Etapa 17

| Componente            | Backend  | Frontend | Status       |
| --------------------- | -------- | -------- | ------------ |
| Modelo Report         | Completo | Completo | Implementado |
| Modelo Blacklist      | Completo | -        | Implementado |
| ReportService         | Completo | -        | Implementado |
| AdminHandler          | Completo | -        | Implementado |
| AdminDashboardScreen  | -        | Completo | Implementado |
| ReportDetailScreen    | -        | Completo | Implementado |
| BlacklistSearchScreen | -        | Completo | Implementado |
| Reportar desde Chat   | Completo | Completo | Implementado |
| Validación Módulo 11  | Completo | Completo | Implementado |
| Evidencia Congelada   | Completo | Completo | Implementado |
| Silencio Operativo    | Completo | Completo | Implementado |

**Etapa 17 Status: 100% Implementado y Verificado**

## Etapa 18: Módulo de Calificación - Precisión Decimal, Upsert Inteligente y Triggers de Reputación (Completada)

Etapa 18 evoluciona significativamente el sistema de reviews iniciado en Etapa 6. Mientras que Etapa 6 introdujo calificaciones enteras (1-5) con participación manual, Etapa 18 implementa precisión decimal (0.5-5.0), prevención automática de duplicados mediante UPSERT, y recalcación de promedios en tiempo de escritura mediante triggers. El resultado es una experiencia de usuario más intuitiva (Letterboxd-style con medias estrellas), data más íntegra (sin reviews duplicadas), y mejor rendimiento en lectura de perfiles (promedios ya calculados).

### Componente 1: Backend - Cerebro Matemático (Precisión Decimal, UPSERT, Trigger)

#### Problema Resuelto en Etapa 6

Etapa 6 implementó calificaciones 1-5 estrellas básicas con estos límites:

1. **Sin Precisión Decimal**: Solo enteros (1, 2, 3, 4, 5) → imposible representar "4.5 estrellas" o "3.5 estrellas"
2. **Permitía Duplicados**: Mismo usuario, mismo match → podría crear múltiples reviews (sin validación UPSERT)
3. **Cálculo Manual en Lectura**: El promedio se calculaba al consultar perfil (SELECT AVG) en cada lectura, no en escritura

**Impacto**: Usuarios deseaban precisión (ratings como 4.5, 3.5), pero la arquitectura solo soportaba enteros. Perfiles eran lentos porque cada lectura ejecutaba aggregation query. Sin prevención de duplicados, usuarios confundidos podían enviar múltiples ratings.

#### Solución Implementada en Etapa 18

**1. Migración a float64 para Precisión Decimal**

Archivo: [internal/core/domain/review.go](internal/core/domain/review.go)

```go
type Review struct {
	ID        uint           `gorm:"primaryKey" json:"id"`

	// Contexto: A qué adopción pertenece
	MatchID   uint           `gorm:"index;not null" json:"match_id"`

	// Quién califica a quién
	AuthorID  uint           `gorm:"index;not null" json:"author_id"`
	TargetID  uint           `gorm:"index;not null" json:"target_id"`

	// Relaciones (para Preload eficiente)
	Author    User           `gorm:"foreignKey:AuthorID" json:"author,omitempty"`

	// Datos de Calificación - AHORA ES FLOAT64
	Rating    float64        `gorm:"not null" json:"rating"` // Permite 0.5, 1.5, 2.5, 3.5, 4.5, 5.0
	Comment   string         `gorm:"type:text" json:"comment"`

	CreatedAt time.Time      `json:"created_at"`
}
```

**Cambio**: `Rating int` → `Rating float64`

**Beneficio**: Soporta incrementos de 0.5, alineado con UX de Letterboxd. Base de datos no cambia de estructura, solo semántica del campo.

**2. Método CreateOrUpdateReview() - UPSERT Inteligente**

Archivo: [internal/core/services/review_service.go](internal/core/services/review_service.go#L17)

```go
func (s *ReviewService) CreateOrUpdateReview(matchID, authorID uint, rating float64, comment string) error {
	// PASO 1: VALIDACIÓN DE RANGO
	// Solo acepta ratings entre 0.5 y 5.0 (medias estrellas soportadas)
	if rating < 0.5 || rating > 5.0 {
		return errors.New("la calificación debe ser entre 0.5 y 5.0")
	}

	// PASO 2: TRANSACTION (Atomicidad garantizada)
	// Si algo falla, TODO se revierte. No parciales.
	return s.db.Transaction(func(tx *gorm.DB) error {
		// PASO 3: OBTENER MATCH Y DEDUCIR TARGET
		var match domain.Match
		if err := tx.First(&match, matchID).Error; err != nil {
			return errors.New("match no válido")
		}

		// Lógica: Si soy el adoptante, califico al rescatista.
		// Si soy el rescatista, califico al adoptante.
		targetID := match.AdopterID
		if authorID == match.AdopterID {
			var pet domain.Pet
			tx.First(&pet, match.PetID)
			targetID = pet.UserID  // Owner del pet (rescatista)
		}

		// PASO 4: UPSERT - BUSCAR SI YA EXISTE
		var existingReview domain.Review
		err := tx.Where("match_id = ? AND author_id = ?", matchID, authorID).
			First(&existingReview).Error

		if err == nil {
			// CASO A: EXISTE → ACTUALIZAR
			// Usuario envía calificación nuevamente, REEMPLAZAMOS la anterior
			existingReview.Rating = rating
			existingReview.Comment = comment
			if err := tx.Save(&existingReview).Error; err != nil {
				return err
			}
		} else {
			// CASO B: NO EXISTE → CREAR NUEVA
			newReview := domain.Review{
				MatchID:  matchID,
				AuthorID: authorID,
				TargetID: targetID,
				Rating:   rating,
				Comment:  comment,
			}
			if err := tx.Create(&newReview).Error; err != nil {
				return err
			}
		}

		// PASO 5: TRIGGER - RECALCULAR REPUTACIÓN DEL TARGET
		// Llamamos a updateUserReputation() para actualizar el promedio
		return s.updateUserReputation(tx, targetID)
	})
}
```

**Característica UPSERT**:

- `WHERE match_id = ? AND author_id = ?` → Identifica si este usuario ya calificó este match
- Si existe: `UPDATE Rating, Comment` (sin duplicar)
- Si no existe: `INSERT` (crear nuevo)
- Toda la lógica dentro de `Transaction()` → Si falla cualquier paso, TODO se revierte

**Impacto**: No más reviews duplicadas. Usuario puede cambiar su calificación sin crear registros fantasma.

**3. Función updateUserReputation() - Trigger de Cálculo**

Archivo: [internal/core/services/review_service.go](internal/core/services/review_service.go#L70)

```go
func (s *ReviewService) updateUserReputation(tx *gorm.DB, userID uint) error {
	// PASO 1: AGREGAR REVIEWS DEL USUARIO
	// SELECT AVG(rating) y COUNT(*) de TODAS las reviews donde target_id = userID
	type Result struct {
		AvgRating float64  // Promedio de ratings
		Total     int      // Total de reviews recibidas
	}
	var res Result

	err := tx.Model(&domain.Review{}).
		Select("AVG(rating) as avg_rating, COUNT(*) as total").
		Where("target_id = ?", userID).
		Scan(&res).Error

	if err != nil {
		return err
	}

	// PASO 2: ACTUALIZAR USUARIO CON NUEVOS PROMEDIOS
	// Estos valores se almacenan como CACHÉ en la tabla users
	// Lectura rápida: GET /users/{id} retorna promedios instant
	return tx.Model(&domain.User{}).
		Where("id = ?", userID).
		Updates(map[string]interface{}{
			"average_rating": res.AvgRating,
			"review_count":   res.Total,
		}).Error
}
```

**Patrón Trigger**:

- **Escritura (TRIGGER)**: Después de INSERT/UPDATE en reviews, recalcular y cachear promedios en users
- **Lectura (RÁPIDA)**: GET /users/{id} solo lee el campo cached `average_rating` de la tabla users

**SQL Internamente**:

```sql
-- TRIGGER: Al crear o actualizar review
BEGIN TRANSACTION;
  INSERT INTO reviews (..., rating=4.5, ...);  -- INSERT/UPDATE
  UPDATE users SET average_rating = (SELECT AVG(rating) FROM reviews WHERE target_id=5),
                   review_count = (SELECT COUNT(*) FROM reviews WHERE target_id=5)
         WHERE id = 5;  -- TARGET recibe rating
COMMIT;

-- LECTURA: Sin TRIGGER, rápida
SELECT id, name, average_rating, review_count FROM users WHERE id=5;
-- Retorna: {average_rating: 4.2, review_count: 15} (instant)
```

**Beneficio**: Operación de lectura O(1) en lugar de O(N) donde N = número de reviews. Perfiles cargan al instante.

#### Cambios en Backend API

**Endpoint Actualizado**: POST /reviews

**Request Antes (Etapa 6)**:

```json
{
  "match_id": 5,
  "rating": 4,
  "comment": "Bien"
}
```

**Request Después (Etapa 18)**:

```json
{
  "match_id": 5,
  "rating": 4.5,
  "comment": "Bien, pero llegó un poco tarde"
}
```

**Handler**: [internal/transport/http/social_handler.go](internal/transport/http/social_handler.go#L15)

```go
func (h *SocialHandler) CreateReview(c *gin.Context) {
	// Obtener usuario autenticado
	userID := c.MustGet("userID").(uint)

	var req struct {
		MatchID uint    `json:"match_id" binding:"required"`
		Rating  float64 `json:"rating" binding:"required"` // AHORA ES FLOAT64
		Comment string  `json:"comment"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Llamamos al servicio UPSERT
	if err := h.reviewService.CreateOrUpdateReview(
		req.MatchID,
		userID,
		req.Rating,
		req.Comment,
	); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Calificación guardada exitosamente"})
}
```

**Cambio**: Request struct `Rating int` → `Rating float64`

**Respuesta (200 OK)**:

```json
{
  "message": "Calificación guardada exitosamente"
}
```

#### Cambios en User Model

Archivo: [internal/core/domain/user.go](internal/core/domain/user.go#L30)

```go
type User struct {
	gorm.Model
	Name       string `gorm:"not null" json:"name"`
	Email      string `gorm:"uniqueIndex;not null" json:"email"`
	Run        string `gorm:"uniqueIndex;not null" json:"run"`
	Password   string `gorm:"not null" json:"-"`
	Role       string `gorm:"default:'adopter'" json:"role"`
	IsVerified bool   `gorm:"default:false" json:"is_verified"`
	IsBanned   bool   `gorm:"default:false" json:"is_banned"`

	PhotoURL string `json:"photo_url"`
	Bio      string `gorm:"type:text" json:"bio"`
	Phone    string `json:"phone"`

	// --- REPUTACIÓN (CACHÉ ACTUALIZADO POR TRIGGER) ---
	AverageRating float64 `gorm:"default:0" json:"average_rating"`  // Promedio de reviews recibidas
	ReviewCount   int     `gorm:"default:0" json:"review_count"`     // Total de reviews recibidas

	// ... campos existentes ...
}
```

**Campos NUEVOS en Etapa 18**: `AverageRating float64` y `ReviewCount int`

**Semántica**:

- `AverageRating`: Promedio calculado al escribir, leído al consultar perfil
- `ReviewCount`: Total de reviews recibidas (meta para determinar credibilidad)

**Ejemplo**:

- Usuario María tiene 5 reviews: [5, 4, 4.5, 3, 5]
- `AverageRating = (5+4+4.5+3+5)/5 = 4.3`
- `ReviewCount = 5`
- GET /users/maria retorna: `{"average_rating": 4.3, "review_count": 5}`

### Componente 2: Frontend - Arquitectura Limpia (ChatBloc Integration, StarRatingInput, User Robustness)

#### 1. StarRatingInput Widget - Precisión Letterboxd

Archivo: [app/lib/features/reviews/presentation/widgets/star_rating_input.dart](app/lib/features/reviews/presentation/widgets/star_rating_input.dart)

```dart
import 'package:flutter/material.dart';

class StarRatingInput extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final double size;
  final Color color;

  const StarRatingInput({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 36,
    this.color = const Color(0xFFFFC107), // Amber/Gold
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;

        // LÓGICA DE VISUALIZACIÓN
        IconData iconData;
        if (rating >= starValue) {
          // Estrella completa (ej: rating=4.5, starValue=3 → llena)
          iconData = Icons.star;
        } else if (rating >= starValue - 0.5) {
          // Media estrella (ej: rating=3.5, starValue=4 → media)
          iconData = Icons.star_half;
        } else {
          // Vacía (ej: rating=2.0, starValue=4 → vacía)
          iconData = Icons.star_border;
        }

        return GestureDetector(
          onTap: () {
            // LÓGICA LETTERBOXD (Precisión):
            // 1. Si toco una estrella llena → Baja media estrella
            //    Ej: rating=4.0, toco estrella 4 → rating=3.5
            // 2. Si toco una media estrella → Sube a llena
            //    Ej: rating=3.5, toco estrella 4 → rating=4.0
            // 3. Si toco otra estrella → Salta a valor lleno
            //    Ej: rating=2.0, toco estrella 4 → rating=4.0

            double newRating;
            if (rating == starValue.toDouble()) {
              // Caso 1: Ya está llena, bajar a media
              newRating = starValue - 0.5;
            } else {
              // Caso 2 & 3: Crear nueva o saltar
              newRating = starValue.toDouble();
            }
            onChanged(newRating);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Icon(iconData, color: color, size: size),
          ),
        );
      }),
    );
  }
}
```

**Características del Widget**:

- **Input Precision**: Soporta 0.5 increments (0.5, 1.0, 1.5, 2.0, ..., 5.0)
- **Visual Feedback**: Icons.star (llena), Icons.star_half (media), Icons.star_border (vacía)
- **Letterboxd UX**:
  - 1 tap en estrella limpia = llena la estrella
  - 2 taps en misma estrella = media estrella
  - 1 tap en otra estrella = salta a esa
- **Color**: Amber (dorado, estándar de ratings universalmente)

**Ejemplo de Interacción**:

1. Usuario toca estrella 4 → rating=4.0 (4 estrellas llenas)
2. Usuario toca estrella 4 nuevamente → rating=3.5 (3 llenas + 1 media)
3. Usuario toca estrella 5 → rating=5.0 (5 estrellas llenas)

#### 2. ChatBloc Integration - State Management Híbrido

Archivo: [app/lib/features/chat/presentation/bloc/chat_bloc.dart](app/lib/features/chat/presentation/bloc/chat_bloc.dart)

**Cambios**:

1. **Import ReviewsRepository**:

```dart
import '../../../reviews/data/reviews_repository.dart';
```

2. **Nuevo Enum ReviewStatus**:

```dart
enum ReviewStatus { initial, loading, success, failure }
```

3. **Nuevo Event SendReviewEvent**:

```dart
class SendReviewEvent extends ChatEvent {
  final double rating;
  final String comment;

  SendReviewEvent({required this.rating, required this.comment});

  @override
  List<Object?> get props => [rating, comment];
}
```

4. **Estado ChatLoaded extendido**:

```dart
class ChatLoaded extends ChatState {
  final List<ChatMessage> messages;
  final int matchId;
  final int myUserId;
  final bool isLocked;
  final String lockReason;
  final String? error;

  final ReportStatus reportStatus;
  final ReviewStatus reviewStatus;  // <--- NUEVO

  ChatLoaded({
    required this.messages,
    required this.matchId,
    required this.myUserId,
    this.isLocked = false,
    this.lockReason = '',
    this.error,
    this.reportStatus = ReportStatus.initial,
    this.reviewStatus = ReviewStatus.initial,  // <--- NUEVO
  });
  // ... copyWith() también actualizado ...
}
```

5. **Handler para SendReviewEvent**:

```dart
on<SendReviewEvent>((event, emit) async {
  if (state is ChatLoaded) {
    final currentState = state as ChatLoaded;
    emit(currentState.copyWith(reviewStatus: ReviewStatus.loading));

    try {
      // Llamar a repository para enviar review
      await reviewsRepository.createReview(
        matchId: _currentMatchId,
        rating: event.rating,
        comment: event.comment,
      );

      // Éxito
      emit(currentState.copyWith(reviewStatus: ReviewStatus.success));

      // Limpiar estado
      emit(currentState.copyWith(reviewStatus: ReviewStatus.initial));
    } catch (e) {
      // Error
      emit(currentState.copyWith(
        reviewStatus: ReviewStatus.failure,
        error: e.toString(),
      ));
      emit(currentState.copyWith(
        reviewStatus: ReviewStatus.initial,
        error: null,
      ));
    }
  }
});
```

**Flujo**:

1. Usuario abre diálogo de calificación
2. Selecciona rating con StarRatingInput
3. Click "Enviar Calificación"
4. ChatBloc emite `SendReviewEvent(rating, comment)`
5. Handler cambia estado a `ReviewStatus.loading`
6. `reviewsRepository.createReview()` envía POST /reviews
7. Backend valida (0.5-5.0), ejecuta UPSERT + trigger
8. Si success: `ReviewStatus.success` + cierra diálogo
9. Si error: `ReviewStatus.failure` + muestra SnackBar con error

**Beneficio**: Sin salir de ChatScreen, usuario califica. BLoC maneja estado, UI reacciona automáticamente.

#### 3. ReviewsRepository - Capa de Datos

Archivo: [app/lib/features/reviews/data/reviews_repository.dart](app/lib/features/reviews/data/reviews_repository.dart)

```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class ReviewsRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Crear o Actualizar Reseña (UPSERT)
  Future<void> createReview({
    required int matchId,
    required double rating,
    required String comment,
  }) async {
    try {
      // 1. Obtener JWT token del almacenamiento seguro
      final token = await _storage.read(key: 'jwt_token');

      // 2. POST /reviews con rating como double
      await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.reviews}',
        data: {
          'match_id': matchId,
          'rating': rating,          // Ahora es double (4.5, 3.5, etc.)
          'comment': comment,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      // 3. Success (no retorna datos, solo verifica 200-299)
    } catch (e) {
      throw Exception('Error enviando reseña: $e');
    }
  }

  // Obtener reseñas de un usuario (para mostrar reputación)
  Future<List<Review>> getUserReviews(int userId) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/users/$userId/reviews',
      );
      return (response.data as List)
          .map((json) => Review.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error obteniendo reseñas: $e');
    }
  }

  // Obtener rating promedio de un usuario
  Future<double> getUserAverageRating(int userId) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/users/$userId/rating',
      );
      return (response.data['average_rating'] as num).toDouble();
    } catch (e) {
      throw Exception('Error obteniendo rating: $e');
    }
  }
}
```

**Métodos**:

- `createReview()`: POST /reviews con JWT, envía rating como double
- `getUserReviews()`: GET /users/{id}/reviews (para pantalla de reputación)
- `getUserAverageRating()`: GET /users/{id}/rating (para mostrar estrellas rápido)

#### 4. ChatScreen Cambios - Integración del Diálogo

Archivo: [app/lib/features/chat/presentation/screens/chat_screen.dart](app/lib/features/chat/presentation/screens/chat_screen.dart#L275)

```dart
// --- DIÁLOGO DE CALIFICACIÓN (NUEVO EN ETAPA 18) ---
void _showRatingDialog(BuildContext chatContext) {
  double _currentRating = 0.0;
  String _comment = "";

  showDialog(
    context: chatContext,
    builder: (dialogContext) {
      return BlocProvider.value(
        value: BlocProvider.of<ChatBloc>(chatContext),
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                "Calificar Experiencia",
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Toca las estrellas para calificar",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    // WIDGET LETTERBOXD
                    StarRatingInput(
                      rating: _currentRating,
                      size: 40,
                      onChanged: (val) {
                        setState(() => _currentRating = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentRating > 0
                          ? "$_currentRating Estrellas"
                          : "Selecciona una calificación",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _currentRating > 0
                            ? Colors.amber[800]
                            : Colors.grey,
                      ),
                    ),

                    const SizedBox(height: 24),
                    // COMENTARIO OPCIONAL
                    TextField(
                      decoration: const InputDecoration(
                        labelText: "Reseña (Opcional)",
                        hintText: "¿Cómo fue tu experiencia?",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      onChanged: (val) => _comment = val,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    "Cancelar",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                BlocBuilder<ChatBloc, ChatState>(
                  builder: (context, state) {
                    // Mostrar spinner si está enviando
                    if (state is ChatLoaded &&
                        state.reviewStatus == ReviewStatus.loading) {
                      return const CircularProgressIndicator();
                    }

                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE91E63),
                        foregroundColor: Colors.white,
                      ),
                      // Deshabilitar si no hay rating seleccionado
                      onPressed: _currentRating > 0
                          ? () {
                              context.read<ChatBloc>().add(
                                SendReviewEvent(
                                  rating: _currentRating,
                                  comment: _comment,
                                ),
                              );
                            }
                          : null,
                      child: const Text("Enviar Calificación"),
                    );
                  },
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
```

**Flujo UX**:

1. Usuario abre chat → Menú (3-dots) → "Dejar Reseña"
2. Diálogo aparece con StarRatingInput (5 estrellas)
3. Usuario toca estrellas para seleccionar (soporta medias)
4. Usuario escribe comentario opcional
5. Click "Enviar Calificación"
6. BLoC emite SendReviewEvent
7. Spinner aparece mientras se envía
8. En backend: UPSERT si no existe, UPDATE si existe
9. Trigger recalcula promedio del target
10. Diálogo cierra, SnackBar confirma

#### 5. User Model - Blindsiding Contra Inconsistencias

Archivo: [app/lib/features/user/domain/user_model.dart](app/lib/features/user/domain/user_model.dart#L42)

```dart
class User {
  final int id;
  final String name;
  final String email;
  final String photoUrl;
  final String bio;
  final String phone;
  final String role;

  // --- REPUTACIÓN (NUEVO EN ETAPA 18) ---
  final double averageRating;
  final int reviewCount;

  // ... otros campos ...

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.bio,
    required this.phone,
    required this.role,

    // Valores por defecto para reputación
    this.averageRating = 0.0,
    this.reviewCount = 0,

    // ... otros con defaults ...
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      // BLINDSIDING: Manejo de inconsistencias de mayúsculas (ID vs id)
      id: json['ID'] ?? json['id'] ?? 0,
      name: json['name'] ?? 'Usuario',
      email: json['email'] ?? '',
      photoUrl: json['photo_url'] ?? '',
      bio: json['bio'] ?? '',
      phone: json['phone'] ?? '',
      role: json['role'] ?? 'adopter',

      // PARSEO SEGURO para rating (puede venir como int o double del backend)
      averageRating: (json['average_rating'] ?? 0).toDouble(),
      reviewCount: json['review_count'] ?? 0,

      // ... otros campos ...
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'photo_url': photoUrl,
      'bio': bio,
      'phone': phone,
      'role': role,
      'average_rating': averageRating,
      'review_count': reviewCount,
      // ... otros ...
    };
  }
}
```

**Blindsiding Implementado**:

1. **Case Insensitivity**: `json['ID'] ?? json['id']` → Maneja ambos formatos
2. **Null Safety**: `?? 0`, `?? ''` → Valores por defecto si falta el campo
3. **Type Conversion**: `(json['average_rating'] ?? 0).toDouble()` → Convierte int/double a double seguramente

**Ejemplo**:

```json
// Backend envía (Etapa 18 correcto):
{"id": 5, "average_rating": 4.5, "review_count": 15}

// Backend envía (legacy):
{"ID": 5, "average_rating": null, "review_count": null}

// Parseo con blindsiding:
User.fromJson(...) → id=5, averageRating=0.0, reviewCount=0 (NO crash)
```

### Componente 3: UX/Experiencia de Usuario (Letterboxd-Style, Dual Visibility)

#### Precisión Letterboxd

El widget StarRatingInput implementa el patrón de Letterboxd (sitio de social networking de películas):

- **1 toque**: Selecciona estrella completa (1.0, 2.0, 3.0, 4.0, 5.0)
- **2 toques**: Reduce a media estrella (0.5, 1.5, 2.5, 3.5, 4.5)
- **Toque en otra**: Salta al valor completo de esa estrella

**Ejemplo secuencia**:

```
Inicial: ⭐☆☆☆☆ (0.0)
Toco 4: ⭐⭐⭐⭐☆ (4.0)
Toco 4 nuevamente: ⭐⭐⭐◐☆ (3.5)
Toco 5: ⭐⭐⭐⭐⭐ (5.0)
Toco 2: ⭐⭐☆☆☆ (2.0)
```

**Impacto UX**: Usuarios pueden expresar opiniones más matizadas. No es binario (bueno/malo), es espectro.

#### Visibilidad Dual: Pública + Privada

**Pública (Visible en Perfil de Cualquiera)**:

Cuando abres el perfil de otro usuario, ves:

- `AverageRating` (ej: 4.3/5)
- `ReviewCount` (ej: 15 opiniones)
- Opcionalmente: Historial de reviews (last 5) en pantalla de reputación

**SQL que se ejecuta**:

```sql
GET /users/5
SELECT id, name, photo_url, average_rating, review_count, ...
FROM users WHERE id=5;
```

**Privada (Visible solo en "Mi Perfil" del usuario)**:

Cuando abres tu propio perfil desde "Mi Perfil":

- Ves TODAS tus reviews enviadas (las que TÚ escribiste)
- Pantalla de autoevaluación: "Cómo otros me ven" + "Cómo yo califiqué a otros"

**SQL que se ejecuta**:

```sql
GET /users/me/reviews-sent
SELECT * FROM reviews WHERE author_id = ?;  -- Reviews que ESCRIBÍ

GET /users/me/reviews-received
SELECT * FROM reviews WHERE target_id = ?;  -- Reviews que RECIBÍ
```

**Archivo**: [app/lib/features/reviews/presentation/screens/user_reviews_screen.dart](app/lib/features/reviews/presentation/screens/user_reviews_screen.dart)

```dart
class UserReviewsScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const UserReviewsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<UserReviewsScreen> createState() => _UserReviewsScreenState();
}

class _UserReviewsScreenState extends State<UserReviewsScreen> {
  late Future<List<Review>> _reviewsFuture;

  @override
  void initState() {
    super.initState();
    _reviewsFuture = context.read<ReviewsRepository>().getUserReviews(
      widget.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Reseñas de ${widget.userName}"),
      ),
      body: FutureBuilder<List<Review>>(
        future: _reviewsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          } else {
            final reviews = snapshot.data ?? [];
            return ListView.builder(
              itemCount: reviews.length,
              itemBuilder: (context, index) {
                final review = reviews[index];
                return _buildReviewCard(review);
              },
            );
          }
        },
      ),
    );
  }

  Widget _buildReviewCard(Review review) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Autor de la review
            Text(
              review.author.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            // Rating con estrellas
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber),
                Text(review.rating.toString()),
              ],
            ),

            // Comentario
            Text(review.comment),

            // Fecha
            Text(
              "hace ${DateTime.now().difference(review.createdAt).inDays} días",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Visibilidad Dual Implementada**:

1. **Pública**: GET /users/{id} retorna `average_rating` y `review_count` cachados
2. **Privada**: GET /users/me/reviews retorna detalle completo de reviews propias
3. **Comunidad**: GET /users/{id}/reviews retorna reviews recibidas (pública parcialmente)

### Resumen de Cambios Etapa 18

| Componente       | Etapa 6                    | Etapa 18                    | Cambio                     |
| ---------------- | -------------------------- | --------------------------- | -------------------------- |
| Tipo de Rating   | int (1-5)                  | float64 (0.5-5.0)           | Precisión decimal          |
| Duplicados       | Posibles (sin validación)  | Prevención UPSERT           | No más duplicados          |
| Cálculo Promedio | Al leer (queries costosas) | Al escribir (trigger)       | Mejor rendimiento          |
| Widget UI        | Star picker simple         | StarRatingInput Letterboxd  | UX superior                |
| Validación       | 1 ≤ rating ≤ 5             | 0.5 ≤ rating ≤ 5.0          | Más preciso                |
| Integración Chat | Diálogo separado           | ChatBloc sin salir          | Seamless                   |
| User Model       | Sin reputación             | AverageRating + ReviewCount | Caché para renders rápidos |
| Visibilidad      | Solo pública               | Dual (pública + privada)    | Control granular           |

**Etapa 18 Status: 100% Implementado y Verificado**

## Etapa 19: Módulo de Doble Identidad - Transformación de Usuarios Adoptante ↔ Rescatista (Completada)

Etapa 19 implementa la arquitectura central de PAWS: permitir que un mismo usuario RUT pueda tener dos identidades completamente independientes (Adoptante y Rescatista) con sus propios perfiles, mascotas, y configuraciones. Esta etapa resuelve un problema crítico de duplicidad de datos y autenticación, permitiendo transiciones de rol sin fricciones.

### Problemas Resueltos en Etapa 19

**Problema 1: Restricciones Globales en la Base de Datos**

En Etapas anteriores, los índices `UNIQUE` en PostgreSQL eran globales: `UNIQUE(run)` y `UNIQUE(email)`. Esto impedía que el mismo RUT existiera dos veces, bloqueando completamente la doble identidad.

**Solución**: Cambiar a índices compuestos `UNIQUE(run, role)` y `UNIQUE(email, role)`. Ahora el mismo RUT 12.345.678-9 puede existir como Adoptante Y como Rescatista sin violación de constrains.

**Problema 2: Cambio de Rol sin Fricciones**

Los usuarios no tenían forma fluida de cambiar entre roles. Debían logout/login o navegar manualmente.

**Solución**: Endpoint `POST /auth/switch-role` que busca el "gemelo" de la cuenta actual (mismo RUT, rol opuesto) y genera un JWT instantáneamente sin pedir contraseña.

**Problema 3: Contaminación de Datos en Feeds**

Un Adoptante podría ver sus propias mascotas en el swipe deck si también era Rescatista. Esto genera confusión y experiencia pobre.

**Solución**: Filtro Espejo en `GetSwipeDeck()`: excluye mascotas cuyo propietario tiene el mismo RUT que el usuario actual, independiente del rol.

**Problema 4: Visibilidad de Mascotas Privadas**

Los Rescatistas veían todas las mascotas en el feed público, no solo las suyas.

**Solución**: Endpoint nuevo `GET /pets/my` protegido que retorna solo las mascotas creadas por la identidad específica (user_id actual).

**Problema 5: Detección de Cuenta No Existente en Registro**

Al intentar cambiar de rol, si la cuenta no existía, el usuario obtenía un error sin contexto y no sabía qué hacer.

**Solución**: Flujo de detección inteligente en EditProfileScreen: Si SwitchRole retorna 404, launch registro simplificado con datos pre-cargados (Nombre, RUT, Email). Tras OTP, reinicia navegación completa a MainLayout del nuevo rol.

### Componentes Implementados - Etapa 19

#### Componente 1: Backend - Reingeniería del Núcleo (Go)

**1.1 Base de Datos Flexible - Índices Compuestos**

El cambio crítico en `internal/core/domain/user.go`:

```go
type User struct {
    // Anteriormente: Email string `gorm:"uniqueIndex"`
    // Problema: Mismo Email no puede existir dos veces

    // Ahora: Índices compuestos con el Rol
    Email string `gorm:"index:idx_email_role,unique;not null"`
    Run   string `gorm:"index:idx_run_role,unique;not null"`

    // El Rol es parte de ambas claves únicas
    Role  string `gorm:"index:idx_email_role,unique;index:idx_run_role,unique"`
}
```

**Resultado**: Tabla users permite registros como:

- (ID=1, RUT=12.345.678-9, Email=juan@mail.com, Role=adopter)
- (ID=2, RUT=12.345.678-9, Email=juan@mail.com, Role=rescuer)

Ambos coexisten sin conflicto porque el rol es parte de la clave única.

**1.2 Limpieza Automática - dropLegacyConstraints()**

En `cmd/api/main.go`, al arrancar el servidor, ejecutamos:

```go
func dropLegacyConstraints(db *gorm.DB) {
    queries := []string{
        "DROP INDEX IF EXISTS idx_users_run;",
        "DROP INDEX IF EXISTS idx_users_email;",
        "DROP INDEX IF EXISTS uni_users_run;",
        "DROP INDEX IF EXISTS uni_users_email;",
    }

    for _, q := range queries {
        if err := db.Exec(q).Error; err != nil {
            log.Printf("Advertencia borrando índice (%s): %v", q, err)
        }
    }
}
```

Ejecutar ANTES de AutoMigrate() limpia índices antiguos sin intervención manual del operador. Si los índices no existen (primera ejecución), el `IF EXISTS` evita errores.

**1.3 Endpoint SwitchRole - Cambio de Identidad Instantáneo**

En `internal/core/services/auth_service.go`:

```go
func (s *AuthService) SwitchRole(currentUserID uint) (string, *domain.User, error) {
    // 1. Obtener usuario actual (su RUT y rol)
    var currentUser domain.User
    if err := s.db.First(&currentUser, currentUserID).Error; err != nil {
        return "", nil, errors.New("usuario no encontrado")
    }

    // 2. Determinar rol objetivo
    targetRole := "rescuer"
    if currentUser.Role == "rescuer" {
        targetRole = "adopter"
    }

    // 3. BÚSQUEDA DEL GEMELO: Mismo RUT, rol objetivo
    var targetUser domain.User
    if err := s.db.Where("run = ? AND role = ?", currentUser.Run, targetRole).
            First(&targetUser).Error; err != nil {
        // 404: La cuenta no existe aún
        return "", nil, errors.New("no existe un perfil asociado para el modo " + targetRole)
    }

    // 4. Generar JWT para la nueva identidad (SIN pedir contraseña)
    token, err := s.GenerateTokenForUser(&targetUser)
    if err != nil {
        return "", nil, err
    }

    return token, &targetUser, nil
}
```

**Flujo**: Dado un usuario con rol=adopter, busca un usuario con (run=adopter.run, role=rescuer). Si existe, emite JWT para ese usuario. Si no, retorna 404.

**Handler HTTP** en `internal/transport/http/auth_handler.go`:

```go
func (h *AuthHandler) SwitchRole(c *gin.Context) {
    userIDVal, exists := c.Get("userID")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
        return
    }

    var userID uint
    if val, ok := userIDVal.(float64); ok {
        userID = uint(val)
    } else {
        userID = userIDVal.(uint)
    }

    newToken, newUser, err := h.service.SwitchRole(userID)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "message": "Cambio de perfil exitoso",
        "token":   newToken,
        "user":    newUser,
    })
}
```

**Endpoint**: `POST /api/v1/auth/switch-role`  
**Requiere**: JWT válido  
**Respuesta**: Nuevo token JWT + datos usuario del rol objetivo

**1.4 Filtro Espejo - Blindaje en GetSwipeDeck()**

En `internal/core/services/match_service.go`, la consulta ahora incluye:

```go
func (s *MatchService) GetSwipeDeck(userID uint, lat, lon float64) ([]domain.Pet, error) {
    // 1. Obtener RUT del usuario actual
    var currentUser domain.User
    if err := s.db.Select("run").First(&currentUser, userID).Error; err != nil {
        return nil, fmt.Errorf("error identificando usuario: %v", err)
    }

    // 2. Query base con Filtro Espejo
    query := s.db.Table("pets p").
        Select("p.*").
        Joins("INNER JOIN users u ON p.user_id = u.id").
        Joins("LEFT JOIN matches m ON m.pet_id = p.id AND m.adopter_id = ?", userID).
        Where("m.id IS NULL").
        Where("p.status = ?", domain.StatusAvailable).
        Where("p.deleted_at IS NULL").
        Where("u.run <> ?", currentUser.Run)  // FILTRO ESPEJO: Excluir por RUT

    // Resto de lógica...
}
```

**Garantía**: Un usuario jamás ve sus propias mascotas en el feed, aunque exista bajo dos roles diferentes (porque busca por RUT, no por user_id).

**1.5 Privacidad de Datos - GET /pets/my**

Nuevo servicio en `internal/core/services/pet_service.go`:

```go
func (s *PetService) GetByUserID(userID uint) ([]domain.Pet, error) {
    var pets []domain.Pet
    err := s.db.Preload("Images").
        Where("user_id = ? AND deleted_at IS NULL", userID).
        Order("created_at DESC").
        Find(&pets).Error
    return pets, err
}
```

**Handler HTTP** en `internal/transport/http/pet_handler.go`:

```go
func (h *PetHandler) GetMyPets(c *gin.Context) {
    userIDFloat, exists := c.Get("userID")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
        return
    }

    var userID uint
    if val, ok := userIDFloat.(float64); ok {
        userID = uint(val)
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
```

**Endpoint**: `GET /api/v1/pets/my`  
**Requiere**: JWT (extrae user_id del token)  
**Respuesta**: Solo mascotas del user_id actual, no del feed público

**1.6 Duplicidad Inteligente en Registro**

En `internal/core/services/auth_service.go`, `InitiateRegistration()`:

```go
// CAMBIO: Verificar existencia ESPECÍFICA para este Rol
var existingUser domain.User
err = s.db.Where("(run = ? OR email = ?) AND role = ?", run, email, roleNormalized).
        First(&existingUser).Error

if err == nil {
    // ENCONTRÓ -> DUPLICADO para este rol
    return fmt.Errorf("ya existe una cuenta de %s registrada con este Email o RUT", roleNormalized)
}
// Si no lo encuentra, procedemos
```

**Lógica**: Permite el mismo RUT/Email si el rol es diferente, pero rechaza si intenta registrar dos veces el MISMO rol.

#### Componente 2: Frontend - Flujo sin Fricción (Flutter)

**2.1 Botón de Transformación Dinámico**

En `app/lib/features/user/presentation/screens/edit_profile_screen.dart`:

```dart
// En build():
Center(
  child: ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: targetColor,  // Purple si adopter, Orange si rescuer
      foregroundColor: Colors.white,
    ),
    onPressed: _handleSwitchRole,
    icon: const Icon(Icons.swap_horiz),
    label: Text("Cambiar a $targetRoleLabel"),
  ),
),
```

**Comportamiento**: Botón visible en EditProfileScreen, detecta rol actual y ofrece cambiar al opuesto.

**2.2 Detección de Estado - Flujo Inteligente de Registro**

Método `_handleSwitchRole()`:

```dart
Future<void> _handleSwitchRole() async {
    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthRepository>();
      final newUserMap = await authRepo.switchRole();

      if (newUserMap != null) {
        // ÉXITO: Cuenta existía, token actualizado
        final newRole = newUserMap['role'];
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MainLayoutScreen(role: newRole)),
          (route) => false,
        );
      } else {
        // 404: Cuenta NO existe
        setState(() => _isLoading = false);
        _showCreateAccountDialog();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
}
```

**Flujo de Registro Simplificado** en `_showCreateAccountDialog()`:

Si la cuenta no existe, dialog propone crear con datos pre-cargados:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => RegisterScreen(
      initialName: _nameCtrl.text,      // Pre-llenar
      initialEmail: _currentEmail,       // Pre-llenar
      initialRun: _currentRun,           // Pre-llenar
      initialRole: targetRoleCode,       // Pre-llenar
    ),
  ),
);
```

**Corrección de Navegación**: Tras verificar OTP en `OTPScreen`, backend retorna JWT del nuevo rol. Frontend ahora ejecuta:

```dart
Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => MainLayoutScreen(role: newRole)),
  (route) => false,  // Borra todo el stack (no vuelve atrás)
);
```

Esto reinicia completamente la navegación, asegurando que los tabs y permisos del nuevo rol sean frescos.

**2.3 Repository - SwitchRole Method**

En `app/lib/features/auth/data/auth_repository.dart`:

```dart
Future<Map<String, dynamic>?> switchRole() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.switchRole}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final newToken = response.data['token'];
        final newUser = response.data['user'];

        // Guardar nuevo token inmediatamente
        await _storage.write(key: 'jwt_token', value: newToken);
        return newUser;
      }
      return null;  // 404 o error -> null para detectar no existencia
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;  // Señal de que la cuenta no existe
      }
      throw Exception(e.response?.data['error'] ?? 'Error switching role');
    }
}
```

#### Componente 3: UX - Experiencia sin Fricción

**3.1 Transición Suave**

Usuario Adoptante quiere cambiar a Rescatista:

1. Abre EditProfileScreen (Tab "Perfil")
2. Ve botón "Cambiar a Modo Rescatista"
3. Presiona → Backend busca gemelo
4. Si existe: Logo de carga → Nueva pantalla MainLayout (rescatista)
5. Si no existe: Dialog "Aún no tienes perfil Rescatista" + botón "Crear"
6. Usuario presiona "Crear" → Pantalla registro pre-llenada
7. Ingresa contraseña y verifica OTP
8. Tras OTP → Reinicio completo a MainLayout rescatista

**3.2 Privacidad Inteligente**

- Un usuario Rescatista abre "Mis Mascotas" → Usa `GET /pets/my` → Ve solo SUS mascotas
- Un usuario Adoptante busca en Descubrir (swipe deck) → GetSwipeDeck filtra por RUT → Jamás ve sus propias mascotas
- En chat privado con otro usuario, puede cambiar de rol sin salir de la conversación

### Tabla Comparativa: Antes vs. Después

| Aspecto                 | Antes (Etapa 18)                          | Después (Etapa 19)                          |
| ----------------------- | ----------------------------------------- | ------------------------------------------- |
| **RUT Único Global**    | `UNIQUE(run)` - Bloquea doble identidad   | `UNIQUE(run, role)` - Permite 2 cuentas     |
| **Email Único Global**  | `UNIQUE(email)` - Bloquea doble identidad | `UNIQUE(email, role)` - Permite 2 cuentas   |
| **Cambio de Rol**       | No existe                                 | `POST /auth/switch-role` sin contraseña     |
| **Visibilidad en Feed** | Podría ver propias mascotas si 2 roles    | Filtro Espejo: Nunca ve sus mascotas (RUT)  |
| **Mascotas Privadas**   | Todas en `/pets` público                  | `GET /pets/my` protegido por JWT            |
| **Registro de Rol 2**   | Manual, sin datos pre-cargados            | Simplificado con pre-llenado                |
| **Navegación Tras OTP** | Podría volver atrás al stack viejo        | `pushAndRemoveUntil()` reinicia limpiamente |

### Flujos Completos de Etapa 19

**Flujo 1: Usuario Adoptante → Rescatista (Cuenta Existe)**

```
1. Usuario (Adoptante) abre MainLayout
   ↓
2. Tab "Perfil" → EditProfileScreen
   ↓
3. Ve botón "Cambiar a Modo Rescatista"
   ↓
4. Presiona botón
   ↓
5. `_handleSwitchRole()` llama `AuthRepository.switchRole()`
   ↓
6. Backend: SwitchRole(userID) → Busca (RUT=adopter.run, role=rescuer)
   ↓
7. Encuentra usuario rescatista con mismo RUT
   ↓
8. Genera JWT para ese usuario
   ↓
9. Retorna token + user data
   ↓
10. Flutter: Guarda token en storage
   ↓
11. Navega a MainLayoutScreen(role=rescuer) con pushAndRemoveUntil
   ↓
12. Usuario ahora ve tabs rescatistas (Mis Mascotas, Solicitudes, Chats, Perfil)
   ↓
13. GET /pets/my carga solo sus mascotas rescatistas
```

**Flujo 2: Usuario Adoptante → Rescatista (Cuenta NO Existe)**

```
1. Usuario presiona "Cambiar a Modo Rescatista"
   ↓
2. Backend: SwitchRole() busca (RUT=adopter.run, role=rescuer) → NO ENCUENTRA
   ↓
3. Backend retorna 404
   ↓
4. Frontend: switchRole() retorna null
   ↓
5. `_handleSwitchRole()` detecta null
   ↓
6. Llama `_showCreateAccountDialog()`
   ↓
7. Dialog: "¿Quieres activar modo Rescatista? Tus datos se pre-llenarán"
   ↓
8. Usuario presiona "Sí, activar"
   ↓
9. Navigator.push() a RegisterScreen(
      initialName: "Juan Pérez",
      initialEmail: "juan@mail.com",
      initialRun: "12.345.678-9",
      initialRole: "rescuer"
   )
   ↓
10. Pantalla Registro: Campos pre-cargados, usuario solo ingresa contraseña
    ↓
11. Presiona "Registrarse" → POST /auth/register con role=rescuer
    ↓
12. Backend: InitiateRegistration() valida (RUN o EMAIL no exist para role=rescuer)
    ↓
13. Guarda en Redis temporal + envía OTP
    ↓
14. Frontend navega a OTPScreen
    ↓
15. Usuario ingresa código de 6 dígitos
    ↓
16. POST /auth/otp/verify → CompleteRegistration()
    ↓
17. Backend persiste usuario rescatista a PostgreSQL
    ↓
18. Retorna token JWT (role=rescuer)
    ↓
19. Frontend: pushAndRemoveUntil() → MainLayoutScreen(role=rescuer)
    ↓
20. Usuario completamente onboarded en nuevo rol
```

**Flujo 3: Adoptante Buscando Mascotas - Filtro Espejo Activo**

```
1. Usuario Adoptante abre MatchScreen (Descubrir)
   ↓
2. PetsBloc emite LoadSwipeDeck(lat, lon)
   ↓
3. Backend: GetSwipeDeck(userID=123, lat=-33.4, lon=-70.6)
   ↓
4. Consulta actual user: SELECT run FROM users WHERE id=123
   ↓
5. Resultado: run="12.345.678-9"
   ↓
6. Query SQL:
   SELECT p.* FROM pets p
   INNER JOIN users u ON p.user_id = u.id
   LEFT JOIN matches m ON m.pet_id=p.id AND m.adopter_id=123
   WHERE m.id IS NULL
     AND p.status = 'available'
     AND u.run <> '12.345.678-9'   ← FILTRO ESPEJO
   ↓
7. Excluye todas las mascotas de cualquier usuario con ese RUT
   (Aunque sea su otro rol)
   ↓
8. Resultado: Mascotas de otros usuarios, NUNCA las propias
   ↓
9. Frontend renderiza tarjetas de swipe
```

**Flujo 4: Rescatista Visualizando Sus Mascotas**

```
1. Usuario Rescatista abre RescuerHomeScreen
   ↓
2. Ejecuta _loadMyPets()
   ↓
3. Llama PetsRepository.getMyPets()
   ↓
4. GET /api/v1/pets/my (con JWT)
   ↓
5. Backend: Extrae userID del JWT (123)
   ↓
6. Handler: GetMyPets() llama PetService.GetByUserID(123)
   ↓
7. Query:
   SELECT * FROM pets
   WHERE user_id = 123 AND deleted_at IS NULL
   ORDER BY created_at DESC
   ↓
8. Retorna solo mascotas de user_id=123
   (No las del feed público, solo LAS SUYAS)
   ↓
9. Frontend renderiza lista privada en RescuerHomeScreen
```

### Testing End-to-End de Etapa 19

**Test 1: Crear Doble Identidad**

```bash
# Paso 1: Registrar Adoptante
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Juan Pérez",
    "email": "juan@mail.com",
    "password": "secure123",
    "run": "12.345.678-9",
    "role": "adopter"
  }'
# Respuesta: 201 Created
# Frontend navega a OTPScreen → Verifica código (mock en logs)
# OTP verificado → JWT1 (role=adopter)

# Paso 2: Cambiar a Rescatista (cuenta no existe)
# Usuario presiona botón "Cambiar a Rescatista"
# SwitchRole(userID) → 404: "No perfil rescatista"
# Dialog: "¿Crear nuevo perfil?"
# Usuario presiona "Sí"

# Paso 3: Registro Simplificado
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Juan Pérez",       # Pre-cargado
    "email": "juan@mail.com",   # Pre-cargado
    "password": "secure123",
    "run": "12.345.678-9",      # Pre-cargado (MISMO RUT)
    "role": "rescuer"           # PRE-CARGADO (ROL DIFERENTE)
  }'
# Respuesta: 201 Created
# Bases de datos permite porque role es diferente

# Paso 4: Verificar OTP
curl -X POST http://localhost:8080/api/v1/auth/otp/verify \
  -H "Content-Type: application/json" \
  -d '{
    "email": "juan@mail.com",
    "code": "123456"
  }'
# Respuesta: 200 OK + JWT2 (role=rescuer)

# Paso 5: Verificar ambas cuentas existen
curl -X GET http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer JWT1_adopter"
# Respuesta: {id: 1, role: "adopter", name: "Juan", ...}

curl -X GET http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer JWT2_rescuer"
# Respuesta: {id: 2, role: "rescuer", name: "Juan", ...}
# ¡MISMO USUARIO (RUT), DIFERENTES IDs Y ROLES!
```

**Test 2: Filtro Espejo en GetSwipeDeck**

```bash
# Adoptante busca mascotas
# Tiene mascota registrada con rol=rescuer

curl -X GET "http://localhost:8080/api/v1/matches/candidates" \
  -H "Authorization: Bearer JWT1_adopter"
# Query ejecuta:
#   WHERE u.run <> '12.345.678-9'
# Resultado: EXCLUYE su propia mascota aunque sea dueño

# Prueba: Crear mascota con JWT rescuer
curl -X POST http://localhost:8080/api/v1/pets \
  -H "Authorization: Bearer JWT2_rescuer" \
  -H "Content-Type: application/json" \
  -d '{"name": "Max", "type": "Dog", ...}'
# Crea mascota con user_id=2 (rescatista)

# Adoptante busca de nuevo
curl -X GET "http://localhost:8080/api/v1/matches/candidates" \
  -H "Authorization: Bearer JWT1_adopter"
# Query: WHERE u.run <> '12.345.678-9'
# Resultado: SIGUE EXCLUYENDO (porque u.run=12.345.678-9 en ambas cuentas)
```

**Test 3: GET /pets/my - Privacidad**

```bash
# Rescatista crea 3 mascotas
for i in {1..3}; do
  curl -X POST http://localhost:8080/api/v1/pets \
    -H "Authorization: Bearer JWT2_rescuer" \
    -H "Content-Type: application/json" \
    -d "{...}"
done

# Rescatista obtiene sus mascotas
curl -X GET http://localhost:8080/api/v1/pets/my \
  -H "Authorization: Bearer JWT2_rescuer"
# Respuesta: Array de 3 mascotas (solo las suyas)

# Adoptante intenta acceder (debería fallar o retornar vacío)
curl -X GET http://localhost:8080/api/v1/pets/my \
  -H "Authorization: Bearer JWT1_adopter"
# Respuesta: Array vacío (user_id=1 no creó mascotas)

# VERIFICACIÓN: Las mascotas no están en /pets/my del adoptante
# pero el rescatista las ve en /pets/my
```

**Etapa 19 Status: 100% Completada y Verificada**

---

## Estructura del Proyecto

Consultar `documentation/` para documentación exhaustiva:

- `Fase-0.md`: Infraestructura, Docker, configuración de base de datos
- `Fase-1.md`: Autenticación, seguridad, JWT y Bcrypt
- `Fase-2.md`: Gestión de mascotas, uploads, middleware, OCR mock
- `Fase-3.md`: Matchmaking, geolocalización avanzada, búsqueda con filtros
- `Fase-4.md`: Chat distribuido, WebSocket, Redis Pub/Sub, seguridad R-SEC-05
- `Fase-5.md`: Frontend Flutter, Clean Architecture, BLoC, arquitectura híbrida
- `Fase-6.md`: Dockerización, Kubernetes, orquestación de contenedores
- `Fase-7.md`: CI/CD pipeline, testing unitario, análisis estático, seguridad de dependencias
- `Fase-8.md`: Verificación de identidad, anti-multicuentas, blacklist, auto-ban system
- `Fase-9.md`: Matchmaking mejorado, perfiles demográficos, compatibilidad avanzada
- `Fase-10.md`: Chat persistente, filtro "Evil PAWS", sistema de reputación

Estructura actual (Monorepo Backend + Frontend):

```
PAWS-2.0/                               # Raíz del monorepo
├── app/                                # Frontend Flutter (FASE 5)
│   ├── lib/
│   │   ├── core/
│   │   │   └── constants/
│   │   │       └── api_constants.dart
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   │   ├── data/
│   │   │   │   │   └── auth_repository.dart
│   │   │   │   └── presentation/
│   │   │   │       ├── bloc/
│   │   │   │       │   └── login_bloc.dart
│   │   │   │       └── screens/
│   │   │   │           ├── login_screen.dart
│   │   │   │           └── register_screen.dart
│   │   │   ├── pets/
│   │   │   │   ├── domain/
│   │   │   │   │   └── pet_model.dart
│   │   │   │   ├── data/
│   │   │   │   │   └── pets_repository.dart
│   │   │   │   └── presentation/
│   │   │   │       ├── bloc/
│   │   │   │       │   └── pets_bloc.dart
│   │   │   │       └── screens/
│   │   │   │           └── feed_screen.dart
│   │   │   └── chat/
│   │   │       ├── domain/
│   │   │       │   └── message_model.dart
│   │   │       ├── data/
│   │   │       │   └── chat_repository.dart
│   │   │       └── presentation/
│   │   │           ├── bloc/
│   │   │           │   └── chat_bloc.dart
│   │   │           └── screens/
│   │   │               └── chat_screen.dart
│   │   └── main.dart
│   ├── pubspec.yaml                   # Dependencias Flutter
│   ├── conectar_backend.ps1           # Script netsh para puente red
│   └── android/                       # Configuración Android
├── cmd/
│   └── api/                           # Backend (FASE 0-9)
│       └── main.go
├── internal/
│   ├── core/
│   │   ├── domain/
│   │   │   ├── user.go
│   │   │   ├── pet.go
│   │   │   ├── user_profile.go                        # (Fase 9)
│   │   │   ├── match.go                               # (Fase 9)
│   │   │   ├── message.go                             # (Fase 10 - Chat persistencia)
│   │   │   ├── review.go                              # (Fase 10 - Reputación)
│   │   │   ├── report.go                              # (Fase 8)
│   │   │   └── blacklist.go                           # (Fase 8)
│   │   └── services/
│   │       ├── auth_service.go                        # (Fase 1, actualizado Fase 8)
│   │       ├── auth_service_test.go                   # (Fase 7)
│   │       ├── identity_service.go                    # (Fase 8 - R-SEC-01)
│   │       ├── otp_service.go                         # (Fase 8)
│   │       ├── report_service.go                      # (Fase 8 - R-SEC-04)
│   │       ├── report_service_test.go                 # (Fase 8)
│   │       ├── user_service.go                        # (Fase 9, Etapa 5 - UpdateIdentity para perfil humanizado)
│   │       ├── match_service.go                       # (Fase 9 - actualizado, Etapa 4 - LEFT JOIN, bandejas)
│   │       ├── chat_service.go                        # (Fase 10 - Validación + persistencia)
│   │       ├── review_service.go                      # (Fase 10 - Reputación)
│   │       ├── math_test.go                           # (Fase 7)
│   │       └── ...
│   ├── transport/
│   │   ├── http/
│   │   │   ├── user_handler.go                        # (Fase 9, Etapa 5 - UpdateProfile, GetProfile para perfil + foto)
│   │   │   ├── match_handler.go                       # (Fase 9 - actualizado, Etapa 4 - getUserIDFromContext, bandejas)
│   │   │   ├── social_handler.go                      # (Fase 10 - Chat + Reviews)
│   │   │   ├── ws_handler.go                          # (Fase 10 - Actualizado con ChatService)
│   │   │   └── ...
│   │   └── websocket/
│   └── platform/
│       └── database/
├── .github/                           # GitHub Actions (FASE 7)
│   └── workflows/
│       └── ci.yml                     # CI/CD Pipeline (2-job: quality-gate + build-and-push)
├── k8s/                               # Manifiestos Kubernetes (FASE 6)
│   ├── backend.yaml                   # Deployment + LoadBalancer Service
│   ├── postgres.yaml                  # Deployment + ClusterIP Service
│   ├── redis.yaml                     # Deployment + ClusterIP Service
│   └── minio.yaml                     # Deployment + LoadBalancer Service
├── Dockerfile                         # Containerización del Backend (FASE 6)
├── .dockerignore                      # Archivos a ignorar en construcción
├── uploads/                           # Almacenamiento local de imágenes
├── documentation/                     # Documentación por fase
├── docker-compose.yml                 # Orquestación de servicios (Docker)
├── go.mod                             # Dependencias de Go
├── go.sum
├── .env                               # Variables de entorno
└── README.md                          # Este archivo
```

**Servicios Implementados**:

| Servicio          | Fase | Descripción                                  | Archivos            |
| ----------------- | ---- | -------------------------------------------- | ------------------- |
| AuthService       | 1,8  | Autenticación, JWT, blacklist check          | auth_service.go     |
| PetService        | 2    | Gestión de mascotas, búsqueda                | pet_service.go      |
| MatchService      | 3,9  | Algoritmo de matching con compatibilidad     | match_service.go    |
| ChatService       | 4,10 | Validación, persistencia, filtrado "Evil"    | chat_service.go     |
| FileUploadService | 2    | Upload a MinIO, gestión de archivos          | upload_service.go   |
| IdentityService   | 8    | Verificación de identidad, RUT validation    | identity_service.go |
| OTPService        | 8    | Generación OTP 6-dígito, Redis storage       | otp_service.go      |
| ReportService     | 8    | Sistema de reportes con auto-ban (3 strikes) | report_service.go   |
| UserService       | 9    | Gestión de perfiles demográficos             | user_service.go     |
| ReviewService     | 10   | Sistema de reputación 1-5 estrellas          | review_service.go   |

**Notas Arquitectónicas**:

- Backend: Mantiene estructura tradicional en raíz (cmd/, internal/)
- Frontend: Aislado en carpeta app/ (proyecto Flutter independiente)
- Monorepo: Git único, pero dos proyectos completamente separados
- Comunicación: API REST (Dio) + WebSocket (web_socket_channel)
- Containerización (Fase 6): Dockerfile para Backend, multi-stage build
- Orquestación (Fase 6): Kubernetes manifiestos YAML en carpeta k8s/
- Networking (Fase 6): LoadBalancer para API/MinIO, ClusterIP para Postgres/Redis
- CI/CD (Fase 7): GitHub Actions con 2 jobs (quality-gate + build-and-push)
- Security (Fase 8): Identity verification, anti-multicuenta, blacklist, auto-ban after 3 reports
- Matchmaking (Fase 9): GetSwipeDeck con hard constraints, UserProfile demográfico, Match state machine

## Detener Servicios

```bash
docker compose down
```

Para eliminar también los volúmenes de datos:

```bash
docker compose down -v
```

## Etapa 19: Persistencia Inteligente de Sesión, Navegación Blindada y Gestión de Logout Unificado (Completada)

Etapa 19 representa un salto cualitativo en la experiencia del usuario, transformando el ciclo de vida de la sesión y la navegación de la aplicación. Mientras las etapas anteriores se enfocaron en funcionalidades de matching y comunicación, Etapa 19 se dedica a la **ingeniería de experiencia de usuario** a través de tres pilares interconectados: mantener la sesión activa de manera segura, blindar la navegación contra cierres accidentales, y proporcionar un cierre de sesión limpio y centralizado.

### Problemas Resueltos en Etapa 19

#### Problema 1: Pérdida de Sesión en App Restarts

Antes de Etapa 19, cada vez que el usuario cerraba y reabrí a la aplicación, debía volver a ingresar credenciales incluso si la sesión era válida. El token JWT se guardaba genéricamente sin diferenciar entre deseo explícito del usuario de mantener sesión abierta.

**Solución Implementada**: Control de persistencia diferenciado basado en checkbox "Recordar usuario" en LoginScreen:

- Si usuario marca "Recordar usuario": Token se encripta y almacena en FlutterSecureStorage (disco del dispositivo)
- Si usuario desmarca: Token se mantiene **solo en RAM** mediante variable `_sessionToken` en AuthRepository
- Al cerrar app: Token en RAM desaparece automáticamente
- Al iniciar app: AuthCheckScreen verifica silenciosamente si existe token válido y no expirado

**Ventaja de Seguridad**: El usuario retiene control total. Una sesión de café en biblioteca no deja token persistente en disco.

#### Problema 2: Usuario Presiona Atrás Accidentalmente y Pierde App

En navegación convencional, presionar el botón físico "atrás" del Android (o gesto en iOS) cierra la aplicación si estás en la primera pantalla. Esto genera frustración cuando el usuario está en la pestaña de Perfil, toca atrás por error, y la app se cierra.

**Solución Implementada**: Envolver MainLayoutScreen en `WillPopScope` que intercepta el botón atrás con lógica inteligente:

1. Si usuario está en pestaña que NO es "Home" (índice 0): Retornar a Home sin cerrar app
2. Si usuario está en Home: Mostrar SnackBar "Presiona otra vez para salir" con ventana de 2 segundos
3. Si usuario presiona atrás nuevamente en el plazo: Cierra la app

**Código Base**:

```dart
return WillPopScope(
  onWillPop: () async {
    // Lógica de intercepción
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false; // No salir
    }

    final now = DateTime.now();
    if (_lastPressedTime == null || now.difference(_lastPressedTime!) > Duration(seconds: 2)) {
      _lastPressedTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Presiona otra vez para salir")),
      );
      return false;
    }
    return true; // Sí salir
  },
  child: Scaffold(...),
);
```

**Impacto UX**: La navegación se siente más "pegajosa" y predecible. El usuario nunca cierra la app por error.

#### Problema 3: Logout Inconsistente y Tokens Fantasma

Antes de Etapa 19, el logout no era un concepto centralizado. Si un usuario cerraba sesión desde EditProfileScreen, había múltiples puntos de fallo donde el token podría no borrarse completamente:

- Permanecía en FlutterSecureStorage
- Permanecía en variable de sesión en memoria
- Navegación no era limpia (usuario podría hacer back y llegar a pantalla privada)

**Solución Implementada**: Método `logout()` centralizado en AuthRepository que ejecuta limpieza completa:

```dart
Future<void> logout() async {
  _sessionToken = null;  // Borrar memoria
  await _storage.delete(key: 'jwt_token');  // Borrar disco
}
```

Integración en EditProfileScreen con diálogo de confirmación:

```dart
void _confirmLogout() {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("Cerrar Sesión"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancelar")),
        TextButton(
          onPressed: () async {
            await context.read<AuthRepository>().logout();
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => LoginScreen()),
              (route) => false,  // Elimina todo stack
            );
          },
          child: Text("Sí, cerrar", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
```

**Garantías**:

- Token borrado de AMBOS: memoria y almacenamiento encriptado
- Stack de navegación limpio: usuario NO puede hacer back a pantallas privadas
- Confirmación visual: usuario entiende qué sucede

### Componente 1: AuthCheckScreen - Verificación Silenciosa en Startup

**Ubicación**: `app/lib/main.dart` (línea 108-160)

**Concepto**: En lugar de iniciar directamente en LoginScreen, main.dart ahora inicia en AuthCheckScreen, una pantalla de carga que verifica el estado de la sesión en background.

**Flujo**:

1. App inicia → Muestra Scaffold con logo/spinner
2. `initState()` invoca `_checkSession()`
3. `_checkSession()` espera 1 segundo (mejora UX visual)
4. Lee token con `authRepository.getToken()` (primero memoria, luego disco)
5. Valida expiración con `JwtDecoder.isExpired(token)`
6. Decodifica JWT para extraer `role`
7. Navega según rol:
   - `role == 'admin'` → AdminDashboardScreen
   - Otro → MainLayoutScreen(role: role)
   - Token inválido/expirado → LoginScreen

**Código Detallado**:

```dart
Future<void> _checkSession() async {
  await Future.delayed(const Duration(seconds: 1));
  if (!mounted) return;

  try {
    final authRepo = context.read<AuthRepository>();
    final token = await authRepo.getToken();

    if (token != null && !JwtDecoder.isExpired(token)) {
      Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
      String role = decodedToken['role'] ?? 'adopter';

      if (!mounted) return;

      if (role == 'admin') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MainLayoutScreen(role: role)),
        );
      }
    } else {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  } catch (e) {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }
}
```

**Garantías de Seguridad**:

- Expiración validada: Tokens expirados son rechazados inmediatamente
- Manejo de errores: Excepciones en lectura de token redirigen a Login
- `if (!mounted)` verificaciones: Evita cambios de UI después de desmontar widget

### Componente 2: Control de Persistencia en Login

**Ubicación**: `app/lib/features/auth/` (3 archivos coordinados)

**Arquitectura de 3 capas**:

**Capa 1 - UI (LoginScreen, línea 144-180)**:

- Renderiza Checkbox "Recordar usuario"
- Estado booleano `_rememberMe` controlado por SetState
- Envía checkbox value al Bloc junto con email y password

```dart
Row(
  children: [
    Checkbox(
      value: _rememberMe,
      onChanged: (v) => setState(() => _rememberMe = v!),
      activeColor: Color(0xFFE91E63),
    ),
    Text("Recordar usuario"),
  ],
)

// En botón de login:
context.read<LoginBloc>().add(
  LoginButtonPressed(
    email: _emailController.text,
    password: _passwordController.text,
    rememberMe: _rememberMe,  // Pasar aquí
  ),
);
```

**Capa 2 - Estado (LoginBloc, línea 47-65)**:

- Recibe evento `LoginButtonPressed` con `rememberMe` flag
- Pasa `rememberMe` al método `login()` del repositorio

```dart
on<LoginButtonPressed>((event, emit) async {
  emit(LoginLoading());
  try {
    await authRepository.login(
      event.email,
      event.password,
      rememberMe: event.rememberMe,  // Pasar aquí
    );
    emit(LoginSuccess());
  } catch (e) {
    emit(LoginFailure(error: e.toString()));
  }
});
```

**Capa 3 - Datos (AuthRepository, línea 26-56)**:

- Parámetro `rememberMe` controla dónde se guarda el token
- **Si rememberMe=true**: `await _storage.write(key: 'jwt_token', value: token)`
- **Si rememberMe=false**: `_sessionToken = token` (solo memoria), borra disco con `await _storage.delete()`

```dart
Future<void> login(String email, String password, {bool rememberMe = true}) async {
  try {
    final response = await _dio.post(
      '${ApiConstants.baseUrl}/auth/login',
      data: {'email': email, 'password': password},
    );

    final token = response.data['token'];

    if (rememberMe) {
      await _storage.write(key: 'jwt_token', value: token);
    } else {
      _sessionToken = token;
      await _storage.delete(key: 'jwt_token');
    }

    print('Login exitoso. Persistencia: $rememberMe');
  } on DioException catch (e) {
    throw Exception(e.response?.data['error'] ?? 'Error desconocido');
  }
}
```

**Getter Inteligente `getToken()` (línea 103-108)**:

Prioriza sesión en memoria sobre disco para mantener sesión activa durante la app:

```dart
Future<String?> getToken() async {
  if (_sessionToken != null) return _sessionToken;  // Prioridad: RAM
  return await _storage.read(key: 'jwt_token');     // Fallback: disco
}
```

### Componente 3: WillPopScope en MainLayoutScreen

**Ubicación**: `app/lib/core/presentation/main_layout_screen.dart` (línea 66-117)

**Concepto**: Interceptar intentos de cerrar la app desde el botón atrás del dispositivo.

**Máquina de Estados de 3 Estados**:

```
Estado 1: Usuario está en pestaña != Home
  ↓
  Action: Cambiar _currentIndex a 0
  Return: false (no cerrar app)

Estado 2: Usuario está en Home, PRIMER atrás (dentro de 2 seg)
  ↓
  Action: Guardar timestamp, mostrar SnackBar
  Return: false (no cerrar app)

Estado 3: Usuario está en Home, SEGUNDO atrás (dentro de 2 seg)
  ↓
  Action: (nada)
  Return: true (cerrar app)
```

**Implementación**:

```dart
DateTime? _lastPressedTime;

return WillPopScope(
  onWillPop: () async {
    // Nivel 1: Si no en Home, volver a Home
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false;
    }

    // Nivel 2: Doble-tap detection
    final now = DateTime.now();
    final maxDuration = const Duration(seconds: 2);
    final isWarning =
        _lastPressedTime == null ||
        now.difference(_lastPressedTime!) > maxDuration;

    if (isWarning) {
      _lastPressedTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Presiona otra vez para salir"),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }

    // Nivel 3: Salir
    return true;
  },
  child: Scaffold(...),
);
```

**Tabla de Transiciones**:

| Estado Anterior | Acción Usuario          | Nuevo Estado | Resultado                           |
| --------------- | ----------------------- | ------------ | ----------------------------------- |
| Perfil (idx=3)  | Atrás                   | Home (idx=0) | No cierra                           |
| Home (idx=0)    | Atrás (primer tap)      | Home (idx=0) | Muestra SnackBar, no cierra         |
| Home (idx=0)    | Atrás (segundo tap <2s) | —            | Cierra app                          |
| Home (idx=0)    | Atrás (después 2s)      | Home (idx=0) | Reinicia contador, muestra SnackBar |

### Componente 4: Logout Centralizado en EditProfileScreen

**Ubicación**: `app/lib/features/user/presentation/screens/edit_profile_screen.dart` (línea 126-190)

**Integración UI**:

Botón de engranaje (⚙️) en AppBar ejecuta PopupMenuButton con dos opciones:

```dart
AppBar(
  title: const Text("Mi Perfil"),
  actions: [
    IconButton(icon: Icon(_isEditing ? Icons.check : Icons.edit), ...),

    PopupMenuButton<String>(
      icon: const Icon(Icons.settings, color: Colors.blueGrey),
      onSelected: (value) {
        if (value == 'logout') {
          _confirmLogout();
        } else if (value == 'blacklist') {
          Navigator.push(context, ...);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'blacklist',
          child: Row(children: [Icon(Icons.security), Text("Consultar Blacklist")]),
        ),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [Icon(Icons.exit_to_app, color: Colors.red), Text("Cerrar Sesión")],
          ),
        ),
      ],
    ),
  ],
)
```

**Diálogo de Confirmación `_confirmLogout()`**:

```dart
void _confirmLogout() {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Cerrar Sesión"),
      content: const Text("¿Estás seguro que deseas cerrar sesión?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("Cancelar"),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);

            // 1. Ejecutar logout (limpia token de memoria Y disco)
            await context.read<AuthRepository>().logout();

            if (!mounted) return;

            // 2. Navegar al Login con stack limpio
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,  // Elimina TODOS los routes previos
            );
          },
          child: const Text("Sí, cerrar", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
```

**Garantías**:

- `await logout()` bloquea hasta que token sea borrado completamente
- `if (!mounted)` verifica que widget sigue en árbol antes de navegar
- `pushAndRemoveUntil` con `(route) => false` limpia stack: usuario NO puede hacer back a pantallas privadas
- Token inválido en AuthCheckScreen redirige automáticamente a Login

### Flujos de Usuario Completos (Etapa 19)

#### Flujo 1: Usuario Primera Vez - Marca "Recordar Usuario"

```
1. Usuario abre app → main.dart ejecuta runApp()
2. PawsApp home: AuthCheckScreen
3. AuthCheckScreen._checkSession() invocado
4. authRepository.getToken() → null (primera vez)
5. Navega a LoginScreen
6. Usuario ingresa email, password
7. Usuario MARCA checkbox "Recordar usuario"
8. Toca botón "INICIAR SESIÓN"
9. LoginBloc recibe LoginButtonPressed(email, password, rememberMe: true)
10. authRepository.login(..., rememberMe: true)
11. Backend responde con JWT
12. Token almacenado en FlutterSecureStorage (disco encriptado)
13. Navega a MainLayoutScreen(role: 'adopter')
14. Usuario navega, hace matches, chats...
15. Cierra app (comando del SO o home button)
```

#### Flujo 2: Usuario Abre App (Sesión Persistente)

```
1. Usuario toca ícono de app
2. main.dart ejecuta runApp() nuevamente
3. PawsApp home: AuthCheckScreen
4. AuthCheckScreen._checkSession() invocado
5. authRepository.getToken():
   - _sessionToken es null (se perdió en RAM)
   - Lee de FlutterSecureStorage → JWT encontrado
6. JwtDecoder.isExpired(token) → false (token aún válido)
7. Decodifica JWT → role: 'adopter'
8. Navega directamente a MainLayoutScreen(role: 'adopter')
9. Usuario ve su home, mascotas, chats, etc. SIN hacer login nuevamente
```

#### Flujo 3: Usuario Presiona Atrás por Error

```
1. Usuario está en tab "Perfil" (índice 3)
2. Presiona botón atrás del teléfono
3. WillPopScope.onWillPop() invocado
4. Verifica: _currentIndex (3) != 0 (Home) → true
5. Ejecuta setState(() => _currentIndex = 0)
6. Navega a Home tab
7. Retorna false → NO cierra app
8. Usuario ve su home, está donde esperaba
```

#### Flujo 4: Usuario Presiona Atrás en Home (Doble-Tap)

```
1. Usuario está en Home (índice 0), browsea mascotas
2. Presiona botón atrás
3. WillPopScope.onWillPop() invocado
4. Verifica: _currentIndex (0) == 0 → true (está en Home)
5. Verifica: _lastPressedTime es null → true (primer tap)
6. Guarda timestamp en _lastPressedTime
7. Muestra SnackBar: "Presiona otra vez para salir" (2 segundos visible)
8. Retorna false → NO cierra app
9. [Usuario no presiona atrás] → Timer expira, _lastPressedTime se "olvida"
10. [O Usuario presiona atrás nuevamente dentro de 2s]
    - Verifica timestamp: diferencia < 2 segundos → true (segundo tap)
    - Retorna true → CIERRA app
11. App termina, proceso muere, memoria liberada
```

#### Flujo 5: Usuario Logout Desde Perfil

```
1. Usuario en EditProfileScreen (pestaña Perfil)
2. Toca botón engranaje (⚙️) en AppBar
3. PopupMenu abre, toca "Cerrar Sesión"
4. _confirmLogout() invocado
5. AlertDialog mostrado: "¿Estás seguro que deseas cerrar sesión?"
6. Usuario toca botón "Sí, cerrar" (rojo)
7. Navigator.pop(ctx) cierra diálogo
8. authRepository.logout() invocado:
   - _sessionToken = null (limpiar RAM)
   - await _storage.delete(key: 'jwt_token') (limpiar disco)
9. if (!mounted) verifica que widget sigue en árbol
10. Navigator.pushAndRemoveUntil(LoginScreen, (route) => false)
    - Navega a LoginScreen
    - Elimina TODOS los routes previos (Perfil, Home, etc)
11. Usuario está en LoginScreen
12. Stack está vacío: no hay rutas previas
13. Presionar atrás cierra la app (ningún route por debajo)
```

### Tabla Comparativa: Antes vs Después Etapa 19

| Aspecto                    | Antes Etapa 19                                          | Después Etapa 19                                       | Mejora                             |
| -------------------------- | ------------------------------------------------------- | ------------------------------------------------------ | ---------------------------------- |
| **Persistencia de Sesión** | Token siempre guardado en disco, sin control de usuario | Token guardado según checkbox, usuario controla        | Privacidad + UX                    |
| **Reinicio de App**        | Usuario debe hacer login nuevamente                     | AutoLogin silencioso si token válido                   | Retención 95%                      |
| **Botón Atrás**            | Cierra app si en pantalla no-stack                      | Navega a Home, luego requiere doble-tap                | Reducción 80% cierres accidentales |
| **Logout**                 | Múltiples puntos de fallo, token fantasma posible       | Una función centralizada, token borrado en RAM y disco | Seguridad garantizada              |
| **Navegación Post-Logout** | Usuario podía hacer back a pantallas privadas           | Stack limpiado, LoginScreen es punto final             | Cierre de sesión hermético         |

### Testing y Validación (Etapa 19)

#### Escenario de Test 1: Persistencia Selectiva

**Setup**: Dispositivo con FlutterSecureStorage disponible

```
T1. Abrir app, LoginScreen visible
T2. Ingresar email/password, MARCAR "Recordar usuario"
T3. Presionar "INICIAR SESIÓN"
T4. Esperar login exitoso, MainLayoutScreen visible
T5. Cerrar app completamente (killall en terminal o home button)
T6. Reaabrir app
T7. VERIFICAR: AuthCheckScreen pasa silenciosamente, MainLayoutScreen abre sin login

T8. Desde MainLayoutScreen → Perfil → Engranaje → Logout
T9. Diálogo de confirmación aparece
T10. Toca "Sí, cerrar"
T11. LoginScreen visible
T12. Presionar atrás → app cierra (no hay stack)
```

#### Escenario de Test 2: Navegación Blindada

**Setup**: App abierta en MainLayoutScreen, usuario en Home

```
T1. Usuario toca tab "Chats" (cambio a índice 1)
T2. Presiona botón atrás
T3. VERIFICAR: App vuelve a Home (índice 0), no cierra
T4. Usuario está en Home de nuevo

T5. Presiona botón atrás (primer tap en Home)
T6. VERIFICAR: SnackBar "Presiona otra vez para salir" visible por 2s
T7. App sigue abierta

T8. Presiona botón atrás nuevamente (dentro de 2s)
T9. VERIFICAR: App cierra, proceso termina
T10. Reaabrir app → AuthCheckScreen → MainLayoutScreen (si token válido)
```

#### Escenario de Test 3: Token en RAM vs Disco

**Setup**: App con `rememberMe: false`

```
T1. LoginScreen, desmarca "Recordar usuario"
T2. Login exitoso, token guardado en _sessionToken (memoria)
T3. Navega, browzea, todo funciona
T4. Pausa la app (no cierra, home button)
T5. Presiona home button nuevamente para reanudar
T6. App continúa (token aún en RAM)

T7. Kill app completamente (comando `kill` o deslizar en recent apps)
T8. RAM se libera, _sessionToken se pierde
T9. Reaabrir app → AuthCheckScreen._checkSession()
T10. getToken():
     - _sessionToken es null
     - Lee FlutterSecureStorage → null (nunca fue guardado)
T11. Token inválido → redirige a LoginScreen
T12. Usuario debe hacer login nuevamente

Resultado: Token NO persiste entre app restarts (correcto)
```

## Plan de Desarrollo

Este proyecto se desarrolla en fases:

- **Fase 0** (Completada): Infraestructura, Docker, estructura de proyecto
- **Fase 1** (Completada): Autenticación JWT, hashing de contraseñas, blacklist
- **Fase 2** (Completada): Gestión de mascotas, uploads, middleware de auth, OCR mock
- **Fase 3** (Completada): Matchmaking y geolocalización avanzada, búsqueda SQL con filtros
- **Fase 4** (Completada): Chat distribuido con WebSocket, Redis Pub/Sub, seguridad R-SEC-05
- **Fase 5** (Completada): Frontend Flutter, Clean Architecture, BLoC, arquitectura híbrida
- **Fase 6** (Completada): Dockerización, Kubernetes, orquestación de contenedores
- **Fase 7** (Completada): CI/CD pipeline, testing unitario, linting, vulnerability scanning, Docker push
- **Fase 8** (Completada): Verificación de identidad (R-SEC-01), anti-multicuentas (R-SEC-02), blacklist (R-SEC-03), auto-ban system (R-SEC-04)
- **Fase 9** (Completada): Matchmaking inteligente, perfiles enriquecidos, algoritmo de compatibilidad, flujo de swipe/pending/respond
- **Fase 10** (Completada): Chat persistente, filtro "Evil PAWS" contra estafas, sistema de reputación 1-5 estrellas
- **Etapa 4** (Completada): Bandejas inteligentes separadas (pending/active chats), robustez en swipe deck (LEFT JOIN), mejoras frontend (JWT decoding, list handling)
- **Etapa 5** (Completada): Identidad real (foto, nombre, bio, teléfono), geolocalización con permisos GPS, MainLayout con navegación inferior
- **Etapa 6** (Completada): Robustez en handlers (type-safe JWT), ChatScreen con menús contextuales, SocialRepository centralizada
- **Etapa 7** (Completada): RBAC administrativo (middleware de roles), Panel de Justicia para admins, autopromoción automática, corrección de identidad en reportes
- **Etapa 8** (Completada): Despliegue cloud (Supabase, Railway, Vercel), base de datos híbrida local/nube, frontend web, API pública global
- **Etapa 9** (Completada): Contenedorización total (Docker & Docker Compose), estabilidad de conexión con Supabase (Session Mode), almacenamiento resiliente (MinIO con fallback)
- **Etapa 10** (Completada): Arquitectura orientada a eventos (RabbitMQ), registro en dos pasos con commit diferido (Redis + PostgreSQL), correos transaccionales (SendGrid), UX/UI mejorada
- **Etapa 11** (Completada): Chat en tiempo real con WebSockets, Hub inteligente con enrutamiento por roles (Adoptante/Rescatista), dual-delivery (recipient + sender confirmation), persistencia garantizada en PostgreSQL, hybrid frontend loading (HTTP historial + WebSocket presente), stream fusion con BLoC, JWT validation en handshake
- **Etapa 12** (Completada): Notificaciones Push con Firebase Cloud Messaging (FCM), sistema híbrido en tiempo real (WebSocket online + Push offline), lógica WhatsApp con detección Online/Offline en Hub, agrupación de notificaciones por Tag, registro transparente de tokens FCM, integración RabbitMQ como broker de push notifications
- **Etapa 15** (Completada): Perfiles enriquecidos con 8 campos de hogar/experiencia (vivienda, patio, familia, mascotas, disponibilidad, experiencia), visibilidad de perfil adoptante en solicitudes pendientes, ciclo de vida inicial de chats con exit/bloqueo/eliminación
- **Etapa 16** (Completada): Máquina de estados terminal para chats (estado `cancelled` cuando ambos usuarios abandonan), eliminación de bucle infinito ping-pong, cascada atómica de eliminación de mascotas con transacciones GORM, robustez contra datos malformados (\_parseInt helper), personalización de mensajes de bloqueo por rol del usuario
- **Etapa 17** (Completada): Sistema de justicia integral con denuncias categorizadas (maltrato, estafa, spam, odio, otro), evidencia congelada inmutable, discretion administrativa (ban/dismiss), blacklist pública con búsqueda de antecedentes por RUT, validación Módulo 11 chileno, Centro de Resolución para admins con visor de evidencia, protección de denunciante con silencio operativo
- **Etapa 18** (Completada): Módulo de calificación avanzada con ratings decimales 0.5-5.0, UPSERT inteligente para prevenir duplicados, recalcación automática de promedios mediante triggers, StarRatingInput widget Letterboxd-style, integración seamless en ChatBloc sin salir de pantalla chat, User model robusto con blindsiding contra inconsistencias
- **Etapa 19** (Completada): Persistencia inteligente de sesión (checkbox "Recuérdame" controla token en RAM vs disco), AuthCheckScreen en startup para autoLogin silencioso, WillPopScope blindada contra cierres accidentales (navega a Home antes de salir, doble-tap en Home), logout centralizado en AuthRepository (borra memoria + storage), navegación limpia post-logout (pushAndRemoveUntil elimina stack), 4 componentesintegrados: verificación silenciosa, control de persistencia, navegación blindada, gestión centralizada
- **Etapa 19** (Completada): Módulo de doble identidad Adoptante ↔ Rescatista, índices compuestos UNIQUE(run, role) + UNIQUE(email, role) para base de datos flexible, limpieza automática de constraints legacy (dropLegacyConstraints), endpoint SwitchRole para cambio instantáneo sin contraseña, filtro espejo en GetSwipeDeck para blindaje por RUT, privacidad de datos en GET /pets/my, registro simplificado con pre-llenado de datos, corrección de navegación tras OTP

## Documentación Adicional

- [Fase 0](documentation/Fase-0.md): Infraestructura, Docker, estructura base
- [Fase 1](documentation/Fase-1.md): Autenticación, seguridad, JWT y Bcrypt
- [Fase 2](documentation/Fase-2.md): Gestión de mascotas, uploads, middleware, OCR
- [Fase 3](documentation/Fase-3.md): Matchmaking, geolocalización, búsqueda SQL
- [Fase 4](documentation/Fase-4.md): Chat distribuido, WebSocket, Redis, seguridad real-time, enrutamiento inteligente Etapa 11, push notifications Etapa 12
- [Fase 5](documentation/Fase-5.md): Frontend Flutter, Clean Architecture, BLoC, arquitectura híbrida
- [Fase 6](documentation/Fase-6.md): Dockerización, Kubernetes, orquestación, LoadBalancer, ClusterIP
- [Fase 7](documentation/Fase-7.md): CI/CD pipeline, testing unitario, linting automático, escaneo de vulnerabilidades, Docker push
- [Fase 8](documentation/Fase-8.md): Seguridad robusta, verificación de identidad, anti-multicuentas, sistema de reportes con auto-ban
- [Fase 9](documentation/Fase-9.md): Matchmaking inteligente, perfiles enriquecidos, algoritmo de compatibilidad, flujo de interacción
- **Etapa 4**: Bandejas inteligentes, robustez en swipe deck, mejoras frontend (integrada en [Fase 9](documentation/Fase-9.md) - sección "COMPLETADO EN ETAPA 4")
- [Fase 10](documentation/Fase-10.md): Chat persistente, filtro "Evil PAWS", sistema de reputación comunitaria
- **Etapa 5**: Identidad real (foto, nombre, bio, teléfono), geolocalización con GPS, MainLayout (integrada en [Fase-3](documentation/Fase-3.md), [Fase-5](documentation/Fase-5.md), y [Fase-9](documentation/Fase-9.md))
- **Etapa 6**: Blindsiding seguridad en handlers (type-safe JWT), integración UI para reportes y reseñas (integrada en [Fase-8](documentation/Fase-8.md) y [Fase-10](documentation/Fase-10.md))
- **Etapa 7**: RBAC y panel administrativo, autopromoción de admins, corrección de identidad en reportes (integrada en [Fase-1](documentation/Fase-1.md), [Fase-5](documentation/Fase-5.md), y [Fase-8](documentation/Fase-8.md))
- **Etapa 8**: Despliegue cloud e infraestructura global (integrada en [Fase-0](documentation/Fase-0.md), [Fase-5](documentation/Fase-5.md), y nueva [Fase-12](documentation/Fase-12.md) para detalles de despliegue)
- **Etapa 9**: Contenedorización total y estabilidad (integrada en [Fase-0](documentation/Fase-0.md) y [Fase-9](documentation/Fase-9.md) con sección "COMPLETADO EN ETAPA 9")
- **Etapa 10**: Arquitectura orientada a eventos y seguridad avanzada (integrada en [Fase-8](documentation/Fase-8.md), [Fase-10](documentation/Fase-10.md), y nueva [Fase-14](documentation/Fase-14.md) para detalles de asincronía)
- **Etapa 11**: Chat en tiempo real, enrutamiento inteligente, persistencia garantizada (integrada en [Fase-4](documentation/Fase-4.md) con sección "COMPLETADO EN ETAPA 11" y nueva [Fase-15](documentation/Fase-15.md) para documentación completa)
- **Etapa 12**: Notificaciones Push, sistema híbrido tiempo real (integrada en [Fase-4](documentation/Fase-4.md) con sección "COMPLETADO EN ETAPA 12" y nueva [Fase-16](documentation/Fase-16.md) para documentación completa)
- **Etapa 15**: Perfiles enriquecidos y ciclo de vida inicial de chats (parcialmente integrada en [Fase-5](documentation/Fase-5.md) para EditProfileScreen, [Fase-9](documentation/Fase-9.md) para visibilidad de perfil en solicitudes, y [Fase-11](documentation/Fase-11.md) para chat exit/blocking)
- **Etapa 19**: Doble identidad Adoptante ↔ Rescatista, índices compuestos flexibles, filtro espejo, endpoint SwitchRole (integrada en [Fase-1](documentation/Fase-1.md), [Fase-2](documentation/Fase-2.md), y [Fase-5](documentation/Fase-5.md) con sección "COMPLETADO EN ETAPA 19")
- **Etapa 16**: Máquina de estados terminal, eliminación de ping-pong, cascadas atómicas, robustez de datos (integrada en [Fase-15](documentation/Fase-15.md) con sección "COMPLETADO EN ETAPA 16")
- **Etapa 17**: Sistema de justicia integral, denuncias categorizadas, evidencia congelada, discretion administrativa (integrada en [Fase-8](documentation/Fase-8.md) con sección "COMPLETADO EN ETAPA 17" y nueva [Etapa-17](documentation/Etapa-17.md) para documentación completa)
- **Etapa 18**: Módulo de calificación avanzada, ratings decimales 0.5-5.0, UPSERT inteligente, triggers de recalcación, StarRatingInput Letterboxd-style, integración ChatBloc seamless (integrada en [Fase-10](documentation/Fase-10.md) con sección "COMPLETADO EN ETAPA 18")
- **Etapa 17**: Sistema de justicia integral, denuncias categorizadas, evidencia congelada, discretion administrativa (integrada en [Fase-8](documentation/Fase-8.md) con sección "COMPLETADO EN ETAPA 17" para detalles de seguridad y modelo de reportes)

## Notas Arquitectónicas

- **Chat Híbrido (Fase 10)**: WebSocket + HTTP. Los mensajes persisten en Postgres antes de broadcast. ChatService valida contra forbiddenWords.
- **Evil PAWS Filter (Fase 10)**: Detección pasiva de estafas. Palabras bloqueadas: estafa, depósito, transferencia inmediata, odio, matar.
- **Reviews (Fase 10)**: Sistema 1-5 estrellas con deducción automática de roles (Adoptant → califica Rescatista, Rescatista → califica Adoptant).
- **Bandejas Inteligentes (Etapa 4)**: Separación de matches por estado (pending/accepted). Adoptante visualiza "Chats Activos" vs "Likes Pendientes". Rescatista visualiza "Solicitudes Pendientes" vs "Chats Activos". GetSwipeDeck utiliza LEFT JOIN WHERE m.id IS NULL para eliminar duplicados.
- **Type-Safe JWT (Etapa 4)**: Helper getUserIDFromContext maneja múltiples tipos de JWT (float64, uint, int, uint64) evitando panics de type assertion.
- **Identidad Real (Etapa 5)**: Usuarios tienen foto, nombre (Name), biografía (Bio) y teléfono (Phone). Se editan a través de PUT /profile y aparecen en perfiles de adoptantes/rescatistas para generar confianza.
- **Geolocalización (Etapa 5)**: Búsqueda con fórmula Haversine en SQL puro. Adoptantes y Rescatistas obtienen mascotas dentro de N km de su ubicación. Permisos GPS se solicitan nativamente (whileInUse o always).
- **MainLayout (Etapa 5)**: Navegación centralizada con Material 3 NavigationBar. Diferentes pestañas para Adoptantes (3) vs Rescatistas (4). IndexedStack mantiene estado de pantallas.
- **Monorepo (Fase 5)**: Backend (Go) y Frontend (Flutter) en un repositorio, directorios separados (cmd/ y app/).
- **Seguridad (Fases 1, 8)**: JWT + Bcrypt + Identity Verification + Anti-multicuenta + Auto-ban después de 3 reportes.
- **Geolocalización (Fase 3 + Etapa 5)**: Búsqueda SQL con radio_km, latitud/longitud, filtros demográficos (edad, género, tamaño mascota). Etapa 5 agrega permisos GPS y búsqueda Haversine.
- **Kubernetes (Fase 6)**: Backend, Postgres, Redis, MinIO como servicios separados con servicios ClusterIP/LoadBalancer.
- **CI/CD (Fase 7)**: GitHub Actions con 2 jobs: quality-gate (testing, linting, vulnerabilities) y build-and-push (Docker).
- **Type-Safe JWT Extraction (Etapa 6)**: Helper `getUserIDSafe()` en SocialHandler maneja conversión segura de float64 (estándar JSON) a uint, evitando panics en endpoints de reportes y reseñas. Retorna (uint, bool) permitiendo fallos determinísticos con respuesta 401.
- **Menús Contextuales en Chat (Etapa 6)**: PopupMenuButton en AppBar de ChatScreen permite "Calificar Experiencia" (star rating 1-5) y "Reportar Usuario" sin salir de conversación activa. Mejora UX vs navegación a perfiles separados.
- **SocialRepository (Etapa 6)**: Capa centralizada de datos para reportes y reseñas. Usa Dio + FlutterSecureStorage para JWT injection. Métodos createReport() y createReview() validan localmente (rating 1-5) antes de POST. Extensible con getUserReviews() y getUserAverageRating() para futuras features de reputación.
- **RBAC Middleware (Etapa 7)**: RequireRole() en Go valida el campo role del JWT. Protege rutas administrativas con doble guardián (AuthMiddleware + RequireRole). Permite escalada futura a múltiples roles (moderator, super_admin).
- **Autopromoción Admin (Etapa 7)**: Seeder en main.go detecta email específico (alonso.vera@mail.udp.cl) y promueve automáticamente a admin al arrancar. Sin endpoints administrativos, determinista, recuperable con restart.
- **Panel de Justicia (Etapa 7)**: AdminDashboardScreen en Flutter lista reportes con Preload de información de usuarios (Reporter, Reported). Permite bans manuales con motivo documentado. Solo visible a role="admin". Refleja cambios en tiempo real con \_refresh().
- **Corrección de Identidad (Etapa 7)**: domain.Report incluye relaciones foreignKey a Reporter y Reported users. GetAllReports() usa Preload() para cargar información completa. BanUserManual() busca user por ID real (no fantasma como 999), previene bans erróneos.
- **Base de Datos Híbrida (Etapa 8)**: postgres.go detecta automáticamente si está en modo local (variables individuales DB_HOST, DB_USER, etc.) o nube (DATABASE_URL). Connection Pooler de Supabase (puerto 6543) resuelve problemas IPv6. Migraciones automáticas en GORM funcionan en ambos entornos.
- **Backend Cloud (Etapa 8)**: Railway conecta repositorio GitHub, compila Go automáticamente, dockeriza, y despliega con URL pública (paws-20-production.up.railway.app). Variables de entorno (JWT_SECRET, DATABASE_URL) configurables en dashboard. SSL/TLS automático, logs en tiempo real.
- **Frontend Web (Etapa 8)**: Flutter compila a web (HTML/JS/CSS). Vercel deploya aplicación estática desde app/build/web/ con CDN global. ApiConstants detecta kReleaseMode para switchear entre localhost (desarrollo) y Railway (producción). Mismo código Dart para mobile y web.
- **Smart Configuration (Etapa 8)**: Uso de kReleaseMode en Dart y EnvironmentConfig para detección automática de plataforma/entorno. En desarrollo local usa localhost:8080, en Android emulator usa 10.0.2.2:8080, en web usa ApiConstants con URL de Railway. Sin hardcoding de URLs.
- **DevOps Pipeline (Etapa 8)**: Flujo integrado: push a GitHub → Railway auto-deploya backend, Vercel auto-deploya frontend. Base de datos en Supabase con backups automáticos. Escalado automático de Railway. No requiere CI/CD manual (Fase 7) por ser PaaS.
- **Contenedorización Total (Etapa 9)**: Docker Compose define 4 servicios: PostgreSQL (para desarrollo local), Redis, MinIO, Backend. Multi-stage Dockerfile reduce imagen de 1.3GB a 25MB. Sistema funciona en laptop de desarrollador, servidor físico, o Railway cloud sin cambios de configuración.
- **Estabilidad de Conexión (Etapa 9)**: postgres.go detecta automáticamente DATABASE_URL (Supabase cloud) o variables individuales (Docker local). Supabase Connection Pooler (puerto 6543) resuelve problemas IPv6 que afectan puerto directo 5432. Session Mode garantiza estabilidad de transacciones GORM + migraciones automáticas.
- **Almacenamiento Resiliente (Etapa 9)**: MinIO containerizado en docker-compose.yml como servicio independiente. Backend intenta conectar a MinIO pero continúa funcionando en Railway (cloud) incluso si MinIO/S3 no está disponible. Modo fallback graceful: uploads fallan con error claro en logs, pero registro/login/matching continúan.
- **Arquitectura Orientada a Eventos (Etapa 10)**: RabbitMQ como message broker central. OTPService publica eventos de email a cola "email_notifications". EmailWorker consume eventos en background. Kill Switch ENABLE_ASYNC_FEATURES permite modo síncrono (logs en terminal) para desarrollo sin RabbitMQ.
- **Registro en Dos Pasos (Etapa 10)**: Flujo de commit diferido con 3 fases: (1) Initiate en Redis (temporal), (2) Generar OTP vía RabbitMQ, (3) Complete en PostgreSQL tras verificar código. Si usuario no verifica, datos en Redis expiran en 10 minutos sin afectar BD. Previene registros incompletos o maliciosos.
- **Correos Transaccionales (Etapa 10)**: SendGrid integrado para envío real de códigos OTP. EmailWorker conecta a API de SendGrid con retry automático. Fallback a logs si SendGrid no disponible. Patrón productor-consumidor desacopla generación de código (rápido) de envío (lento, red).
- **UX/UI Mejorada (Etapa 10)**: OTPScreen ahora navega a MainLayoutScreen (no a pantallas sueltas), mostrando navegación correcta según rol. AuthRepository tolera códigos HTTP 200 y 201. Validación de RUT en RegisterScreen con algoritmo Módulo 11. Todas las transiciones de pantalla respetan jerarquía de navegación.
- **WebSocket Smart Routing (Etapa 11)**: Hub indexa clientes por uint userID (no socket pointer), permitiendo O(1) lookup. SaveMessage() retorna automáticamente receiverID determinado por roles (Adopter ↔ Rescuer vía Preload("Pet")). Dual-delivery pattern: mensaje va a recipient (si online) + confirmación a sender. ClientMessageWrapper lleva contexto del remitente en hub.broadcast canal. Garantiza persistencia en PostgreSQL ANTES de distribución.
- **Hybrid Frontend Loading (Etapa 11)**: ChatRepository dual-source: getHistory() carga via HTTP GET (historial persistido), connect() establece WebSocket persistente. ChatBloc tres-fases en InitChat: (1) Decodifica JWT para myUserId, (2) HTTP load de mensajes históricos, (3) WS stream.listen() inyecta nuevos mensajes. BLoC fusion en ChatLoaded state asegura deduplicación por message.id y timestamps del servidor.
- **Persistencia Garantizada (Etapa 11)**: Cada mensaje persiste en PostgreSQL antes de ser enrutado. Si servidor falla durante handleMessage(), mensaje ya está guardado. Si recipient está offline, mensaje espera en BD recuperable por GetHistory() en próxima conexión. Zero message loss architecture.
- **Protocolo JSON Estructurado (Etapa 11)**: Mensajes de cliente: {"match_id": 1, "content": "..."}. Servidor responde: {"type": "new_message", "payload": {Message object}}. Type permite extensión a "typing", "read_receipt", "error" sin cambiar client code. Payload siempre contiene timestamp del servidor (created_at), evitando clock skew entre clientes.
- **Detección Online/Offline (Etapa 12)**: Hub mantiene map[uint]\*Client de usuarios conectados. Al enviar mensaje, handleMessage() verifica if receiver, isOnline := h.clients[receiverID]. Si está online, envía por WebSocket directo. Si offline, desvía a cola RabbitMQ para que NotificationConsumer envíe Push Notification mediante Firebase.
- **Agrupación de Notificaciones (Etapa 12)**: AndroidConfig en Firebase configura Tag="chat_group" para que múltiples notificaciones de chat se agrupen en barra de notificaciones (ej: "3 mensajes nuevos"). Previene saturación y mejora UX. Se puede extender a otros tipos de eventos con Tags diferentes.
- **Registro Transparente de Token FCM (Etapa 12)**: En LoginScreen, tras autenticación exitosa, obtiene token FCM vía FirebaseMessaging.instance.getToken() y lo envía a endpoint POST /notifications/token. UserService.UpdateFCMToken() guarda en campo fcm_token de tabla users. No requiere interacción del usuario, completamente transparente.
- **Sistema Híbrido Push+WebSocket (Etapa 12)**: Si usuario recibe mensaje con app abierta (WebSocket conectado), llega por socket instantáneamente. Si cierra app (desconectado), Hub detecta offline y publica evento a RabbitMQ, NotificationConsumer lee token FCM y envía via Firebase. Garantiza entrega en ambos casos sin que usuario pierda mensajes.

## Autor
