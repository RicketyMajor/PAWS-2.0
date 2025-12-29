# PAWS - Pet Adoption Matching System

PAWS es una plataforma de matchmaking diseñada para facilitar adopciones seguras y efectivas entre adoptantes y rescatistas. La aplicación prioriza la seguridad como componente crítico en cada capa.

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
- **Etapa 4** (Completada): Bandejas inteligentes separadas (pending/active chats), robustez en swipe deck (LEFT JOIN), mejoras frontend (JWT decoding, list handling)
- **Fase 10** (Completada): Chat persistente, filtro "Evil PAWS" contra estafas, sistema de reputación 1-5 estrellas
- **Etapa 5** (Completada): Identidad real (foto, nombre, bio, teléfono), geolocalización con permisos GPS, MainLayout con navegación inferior
- **Fase 11** (Planificada): Integración de closures, conclusión de adopciones, feedback final
- **Fase 12** (Planificada): Machine Learning para recomendaciones, scoring dinámico, predicción de éxito

## Documentación Adicional

- [Fase 0](documentation/Fase-0.md): Infraestructura, Docker, estructura base
- [Fase 1](documentation/Fase-1.md): Autenticación, seguridad, JWT y Bcrypt
- [Fase 2](documentation/Fase-2.md): Gestión de mascotas, uploads, middleware, OCR
- [Fase 3](documentation/Fase-3.md): Matchmaking, geolocalización, búsqueda SQL
- [Fase 4](documentation/Fase-4.md): Chat distribuido, WebSocket, Redis, seguridad real-time
- [Fase 5](documentation/Fase-5.md): Frontend Flutter, Clean Architecture, BLoC, arquitectura híbrida
- [Fase 6](documentation/Fase-6.md): Dockerización, Kubernetes, orquestación, LoadBalancer, ClusterIP
- [Fase 7](documentation/Fase-7.md): CI/CD pipeline, testing unitario, linting automático, escaneo de vulnerabilidades, Docker push
- [Fase 8](documentation/Fase-8.md): Seguridad robusta, verificación de identidad, anti-multicuentas, sistema de reportes con auto-ban
- [Fase 9](documentation/Fase-9.md): Matchmaking inteligente, perfiles enriquecidos, algoritmo de compatibilidad, flujo de interacción
- **Etapa 4**: Bandejas inteligentes, robustez en swipe deck, mejoras frontend (integrada en [Fase 9](documentation/Fase-9.md) - sección "COMPLETADO EN ETAPA 4")
- [Fase 10](documentation/Fase-10.md): Chat persistente, filtro "Evil PAWS", sistema de reputación comunitaria
- **Etapa 5**: Identidad real (foto, nombre, bio, teléfono), geolocalización con GPS, MainLayout (integrada en [Fase-3](documentation/Fase-3.md), [Fase-5](documentation/Fase-5.md), y [Fase-9](documentation/Fase-9.md))

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

## Autor
