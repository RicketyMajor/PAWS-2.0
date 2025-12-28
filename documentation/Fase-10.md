# Fase 10: Chat Persistente, Filtrado Inteligente y Sistema de Reputación

## Introducción

Fase 10 es donde el matchmaking inteligente de Fase 9 se vuelve vivo. Habíamos creado un sistema que conecta adoptantes con mascotas compatibles, pero el viaje terminaba en Match.status = accepted. Ahora cerramos el ciclo de confianza completo.

Esta fase es crítica porque introduce tres capas de valor:

1. **Chat Persistente**: El primer cambio fundamental es que el chat ahora tiene memoria. Antes, si recargabas la página, los mensajes desaparecían (eran rebotados ciegamente por WebSocket). Ahora, cada mensaje se valida, guarda en Postgres y persiste para siempre.

2. **Filtrado Inteligente ("Evil PAWS")**: El sistema detecta comportamientos de estafa. Si un usuario intenta enviar "depósito" o "transferencia inmediata", el servidor lo rechaza silenciosamente sin guardar ni difundir. Protege a adoptantes vulnerables de timadores.

3. **Sistema de Reputación**: La confianza requiere historial. Reviews (1-5 estrellas) con comentarios crean un registro permanente. Un rescatista puede tener 5 estrellas, otro 2. La comunidad auto-regula.

Fase 10 = **De "conectar personas" a "construir comunidad de confianza"**.

## Objetivos de la Fase 10

1. Implementar Chat Híbrido (HTTP + WebSockets) con persistencia en BD
2. Crear arquitectura de seguridad pasiva contra estafas (Filtro "Evil PAWS")
3. Implementar validación de contenido en tiempo real
4. Integrar ChatService dentro del ciclo del WebSocket
5. Crear sistema de Reviews con rating 1-5 estrellas
6. Implementar consulta de historial de chat (HTTP GET)
7. Establecer modelo de reputación basado en Reviews
8. Documentar flujos de chat seguro y reviews comunitarias

## Stack Tecnológico - Chat Seguro y Reputación

### Base de Datos

- **Tabla Message (Persistencia)**: Almacena cada conversación

  - MatchID: Contexto (a qué match pertenece)
  - SenderID: Quién envía
  - Content: Texto del mensaje
  - IsRead: Flag de lectura
  - CreatedAt: Timestamp

- **Tabla Review (Reputación)**: Calificaciones de interacciones
  - MatchID: Contexto (qué adopción)
  - AuthorID: Quién califica
  - TargetID: A quién califica
  - Rating: 1-5 estrellas
  - Comment: Texto libre (ej: "llegó tarde", "el perro estaba sucio")

### Servicios

- **ChatService**: Validación, persistencia y filtrado

  - SaveMessage: Guarda con validación "Evil PAWS"
  - GetHistory: Recupera conversaciones previas
  - containsForbiddenContent: Detecta palabras clave de estafa

- **ReviewService**: Gestión de calificaciones
  - CreateReview: Crea rating con validación 1-5
  - Determinación automática de targetID

### Handlers

- **WSHandler**: Orquesta WebSocket + ChatService
- **SocialHandler**: Endpoints HTTP para chat e reviews

## Cambios en la Estructura del Proyecto

### Nuevos Archivos

#### 1. domain/message.go

Modelo que representa un mensaje persistente:

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

**Propósito**: Cada mensaje es un registro permanente. SenderID permite saber quién escribió. IsRead para notificaciones futuras.

#### 2. domain/review.go

Modelo de reputación comunitaria:

```go
type Review struct {
    ID        uint           `gorm:"primaryKey" json:"id"`
    MatchID   uint           `gorm:"index;not null" json:"match_id"`
    AuthorID  uint           `gorm:"index;not null" json:"author_id"`
    TargetID  uint           `gorm:"index;not null" json:"target_id"`
    Rating    int            `gorm:"not null" json:"rating"` // 1-5
    Comment   string         `gorm:"type:text" json:"comment"`
    CreatedAt time.Time      `json:"created_at"`
    DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}
```

**Propósito**: ReviewService determina automáticamente targetID basado en rolesadoptante y rescatista.

#### 3. services/chat_service.go

Corazón de la arquitectura de chat seguro:

```go
type ChatService struct {
    db *gorm.DB
}

var forbiddenWords = []string{
    "estafa", "odio", "matar",
    "depósito", "transferencia inmediata"
}

// SaveMessage: Valida + Guarda + Persiste
func (s *ChatService) SaveMessage(matchID, senderID uint, content string) (*domain.Message, error) {
    // 1. Filtro "Evil PAWS"
    if s.containsForbiddenContent(content) {
        return nil, errors.New("mensaje bloqueado")
    }

    // 2. Verificar Match aceptado
    var match domain.Match
    if err := s.db.First(&match, matchID).Error; err != nil {
        return nil, errors.New("match no encontrado")
    }
    if match.Status != domain.MatchAccepted {
        return nil, errors.New("match no aceptado")
    }

    // 3. Crear y guardar
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

// GetHistory: Recupera conversación previa
func (s *ChatService) GetHistory(matchID uint) ([]domain.Message, error) {
    var messages []domain.Message
    err := s.db.Where("match_id = ?", matchID).
        Order("created_at asc").
        Find(&messages).Error
    return messages, err
}

// containsForbiddenContent: Detecta estafas
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

**Características clave**:

- SaveMessage hace 3 cosas: valida, verifica Match, guarda
- forbiddenWords es lista negra básica (puede venir de BD en producción)
- GetHistory ordena por timestamp (más viejos primero)

#### 4. services/review_service.go

Gestión de reputación comunitaria:

```go
type ReviewService struct {
    db *gorm.DB
}

func (s *ReviewService) CreateReview(matchID, authorID uint, rating int, comment string) error {
    // 1. Validar rating 1-5
    if rating < 1 || rating > 5 {
        return errors.New("rating debe ser 1-5")
    }

    // 2. Obtener Match para determinar roles
    var match domain.Match
    if err := s.db.First(&match, matchID).Error; err != nil {
        return errors.New("match inválido")
    }

    // 3. Determinar a quién se califica
    targetID := match.AdopterID
    if authorID == match.AdopterID {
        // Adoptante califica a Rescatista
        var pet domain.Pet
        s.db.First(&pet, match.PetID)
        targetID = pet.UserID // Dueño de la mascota
    }
    // Si no es adoptante, es rescatista calificando adoptante (targetID ya asignado)

    // 4. Guardar
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

**Lógica de targetID**:

- Adoptante → Califica a Rescatista (pet.UserID)
- Rescatista → Califica a Adoptante (match.AdopterID)

#### 5. transport/http/ws_handler.go (Actualizado, 120 líneas)

PUNTO CRÍTICO: Integración de ChatService en el ciclo WebSocket:

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

// HandleConnections: GET /ws
func (h *WSHandler) HandleConnections(c *gin.Context) {
    // 1. Obtener userID del token
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

    // 3. Registrar cliente en Hub
    client := &Client{
        hub:    h.hub,
        conn:   conn,
        send:   make(chan []byte, 256),
        userID: userID,
    }
    h.hub.register <- client

    // Cleanup
    defer func() {
        h.hub.unregister <- client
        conn.Close()
    }()

    // --- BUCLE PRINCIPAL (PUNTO CLAVE) ---
    for {
        var req IncomingMessage // { match_id, content }

        // Leer JSON del cliente
        err := conn.ReadJSON(&req)
        if err != nil {
            if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
                log.Printf("error websocket: %v", err)
            }
            break
        }

        // --- VALIDACIÓN Y PERSISTENCIA ---
        // Intentamos guardar usando ChatService
        msgSaved, err := h.chatService.SaveMessage(req.MatchID, userID, req.Content)
        if err != nil {
            // Si falla (mala palabra, match no aceptado, etc.)
            // Enviamos error SOLO a este cliente, sin guardar
            errMsg := map[string]string{"error": "Mensaje rechazado: " + err.Error()}
            conn.WriteJSON(errMsg)
            continue
        }

        // --- DIFUSIÓN ---
        // Si se guardó con éxito, lo enviamos al Hub
        response := []byte(msgSaved.Content)
        h.hub.broadcast <- response
    }
}
```

**Flujo de Seguridad**:

1. Cliente envía JSON: `{"match_id": 1, "content": "Hola"}`
2. Handler intercepta en el bucle
3. ChatService.SaveMessage valida 3 cosas:
   - containsForbiddenContent("Hola") → false (OK)
   - Match.status == "accepted" → true (OK)
   - Insert en BD → success (OK)
4. Si todo OK, Hub.broadcast difunde
5. Si FALLA en cualquier paso, mensaje se rechaza sin guardar

#### 6. transport/http/social_handler.go

Endpoints HTTP para chat e reviews:

```go
type SocialHandler struct {
    chatService   *services.ChatService
    reviewService *services.ReviewService
}

// GetChatHistory: GET /matches/:id/messages
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

// CreateReview: POST /reviews
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

#### 7. transport/http/hub.go - Orquestador Central de WebSocket

El Hub es el corazón de la infraestructura WebSocket. Gestiona todas las conexiones activas y distribuye mensajes de forma concurrente usando canales Go.

```go
type Hub struct {
    // Clientes registrados
    clients    map[*Client]bool

    // Canales para registración/desregistración de clientes
    register   chan *Client
    unregister chan *Client

    // Canal para difusión a TODOS los clientes
    broadcast  chan []byte
}

func NewHub() *Hub {
    return &Hub{
        clients:    make(map[*Client]bool),
        register:   make(chan *Client),
        unregister: make(chan *Client),
        broadcast:  make(chan []byte, 256),
    }
}

// Run: Bucle infinito que maneja eventos del Hub
// Este método DEBE ejecutarse en una goroutine: go hub.Run()
func (h *Hub) Run() {
    for {
        select {
        case client := <-h.register:
            // Nuevo cliente se conecta
            h.clients[client] = true
            log.Printf("Cliente registrado. Total: %d", len(h.clients))

        case client := <-h.unregister:
            // Cliente se desconecta
            if _, ok := h.clients[client]; ok {
                delete(h.clients, client)
                close(client.send)
                log.Printf("Cliente desregistrado. Total: %d", len(h.clients))
            }

        case message := <-h.broadcast:
            // Difundir a TODOS los clientes conectados
            for client := range h.clients {
                select {
                case client.send <- message:
                    // Mensaje enviado exitosamente
                default:
                    // Si el canal send está lleno (cliente lento)
                    // lo desconectamos para evitar bloqueo
                    go func(c *Client) {
                        h.unregister <- c
                    }(client)
                }
            }
        }
    }
}
```

**Patrón de Concurrencia**:

- **Mapa `clients`**: Almacena referencias a todos los `Client` activos
- **Canales `register/unregister`**: Sincronización thread-safe de conexiones
- **Canal `broadcast`**: Punto central de difusión de mensajes
- **select en loop infinito**: Multiplexing de 3 tipos de eventos

**Ventajas de este diseño**:

1. **Thread-safe**: Sin mutexes explícitos, los canales sincronizan acceso al mapa
2. **Escalable**: Soporta miles de conexiones simultáneas
3. **Resiliente**: Si un cliente es lento (send lleno), se desconecta sin afectar otros
4. **Simple**: Lógica clara en el bucle principal

**Ejecución en main.go**:

```go
hub := httpTransport.NewHub()
go hub.Run()  // CRÍTICO: ejecutar en goroutine separada
```

#### 8. transport/http/client.go - Representación de Conexión Individual

Cada Cliente representa una conexión WebSocket activa de un usuario.

```go
type Client struct {
    // Referencia al Hub (para desregistración)
    hub *Hub

    // Conexión WebSocket
    conn *websocket.Conn

    // Canal para enviar mensajes a este cliente
    // Buffered (256 bytes) para no bloquear al Hub
    send chan []byte

    // ID del usuario autenticado
    userID uint
}
```

**Responsabilidades de Client**:

- **Mantener conexión viva**: conn es la conexión TCP subyacente
- **Recibir del Hub**: El canal `send` recibe mensajes desde hub.broadcast
- **Identidad**: userID vincula la conexión con el usuario autenticado

**Ciclo de vida**:

1. **Creación** en WSHandler.HandleConnections:

   ```go
   client := &Client{
       hub:    h.hub,
       conn:   conn,
       send:   make(chan []byte, 256),
       userID: userID,
   }
   h.hub.register <- client
   ```

2. **Vida activa**: El cliente está en `h.hub.clients` mapa

   - Lee mensajes en readPump (llamado desde WSHandler)
   - Recibe broadcasts en writePump

3. **Desconexión**:
   ```go
   defer func() {
       h.hub.unregister <- client  // Remover de Hub
       conn.Close()                 // Cerrar TCP
   }()
   ```

**Interacción con Hub**:

```
Cliente (WebSocket)
    |
    +-- send channel ←→ hub.broadcast
                         |
                         v
                    [otro cliente]
                    [otro cliente]
                    [otro cliente]
```

Cuando Hub envía por `broadcast`, TODOS los clientes en el mapa reciben en su canal `send`.

#### 9. Flujo Integrado: Hub + Client + WSHandler

El Hub y Client son **infraestructura concurrente**. WSHandler es quien **orquesta la integración**:

**En HandleConnections**:

```
1. Crear Client con send channel
2. client.hub.register <- client      [Client entra al Hub]
3. Spawnar readPump() goroutine       [Lee del WebSocket]
4. Spawnar writePump() goroutine      [Escribe al WebSocket]
5. Hub.Run() está listening:
   - Si broadcast llega → envía a TODOS los send channels
   - readPump consume desde client.send ← hub.broadcast
   - writePump consume desde client.send ← hub.broadcast
   - Cada writePump escribe al WebSocket del cliente
```

**Diagrama de Goroutines**:

```
main goroutine:
  └─ go hub.Run()              [Goroutine 1: Orquesta central]
  └─ go handler()
       └─ go readPump()        [Goroutine N: Lee de socket N]
       └─ go writePump()       [Goroutine N: Escribe a socket N]
       └─ go readPump()        [Goroutine N+1]
       └─ go writePump()       [Goroutine N+1]
       └─ ... (para cada cliente)
```

**El Hub no conoce de WebSockets, ni de Handlers** → Desacoplamiento perfecto:

- Hub: Maneja clientes y canales (abstracto)
- Client: Estructura con userID y send (simple)
- WSHandler: Integra HTTP/WS con ChatService (orquestación)
- ChatService: Valida y persiste (negocio)

Cada componente tiene una responsabilidad clara.

### Archivos Modificados

#### cmd/api/main.go (Actualizado)

Se integran los nuevos servicios y handlers:

```go
// Servicios
chatService := services.NewChatService(database.DB)
reviewService := services.NewReviewService(database.DB)

// WSHandler ACTUALIZADO (Ahora pasa chatService)
wsHandler := httpTransport.NewWSHandler(hub, chatService)

// NUEVO: SocialHandler
socialHandler := httpTransport.NewSocialHandler(chatService, reviewService)

// En las rutas protegidas:
protected.GET("/matches/:id/messages", socialHandler.GetChatHistory)
protected.POST("/reviews", socialHandler.CreateReview)
protected.GET("/ws", wsHandler.HandleConnections)
```

#### domain/match.go (Status enum verificado)

```go
type MatchStatus string

const (
    MatchPending  MatchStatus = "pending"
    MatchAccepted MatchStatus = "accepted"
    MatchRejected MatchStatus = "rejected"
)
```

Fase 10 valida que `match.Status == MatchAccepted` antes de permitir chat.

## Arquitectura de Chat Híbrido

### Antes (Fase 4 - Tubo Hueco)

```
┌─────────────────────────────────────────────────┐
│ FASE 4: Chat = Tubo Hueco (Sin Persistencia)   │
└─────────────────────────────────────────────────┘

Celular          WebSocket              Hub              Celular 2
  |                  |                    |                  |
  +--"Hola"-------->|                     |                  |
  |                  |--broadcast-------->|---->----------+->|
  |                  |                    |               |  |
  |                  |<--broadcast--------|--Hola---------+  |
  |<--------Hola-----+                    |                  |

Problema: Si se reinicia servidor o recarga página,
          el mensaje desaparece. No hay historial.
```

### Después (Fase 10 - Con ChatService)

```
┌──────────────────────────────────────────────────────────────────┐
│ FASE 10: Chat Persistente + Validación Inteligente              │
└──────────────────────────────────────────────────────────────────┘

Celular          WSHandler             ChatService          Postgres
  |                  |                      |                   |
  +--{JSON}--------->|                      |                   |
  |  {match_id: 1,   |                      |                   |
  |   content:"Hola"}|                      |                   |
  |                  |--SaveMessage-------->|                   |
  |                  |                      ├─ Validar: OK      |
  |                  |                      ├─ Match check: OK  |
  |                  |                      ├─ Insert msg---+-->|
  |                  |                      |<-msg (ID=42)--+   |
  |                  |<-msgSaved-----------+                    |
  |                  |                      |   (Postgres       |
  |                  ├──broadcast-------->Hub-->retiene ID=42)  |
  |                  |                      |                   |
  |<-{id:42, ...}----+                     |                   |

Ventajas:
  1. Mensaje guardado en Postgres (ID=42)
  2. Si reinicia servidor, mensaje persiste
  3. Si recarga página, GetHistory recupera todo
  4. Validación "Evil PAWS" antes de guardar
```

### Flujo Detallado (Vista de Adoptante)

```
┌─────────────────────────────────────────────────────────────────┐
│ Adoptante conecta a chat con Rescatista                         │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
1. WebSocket Connection (Autenticado con Token)
   GET /api/v1/ws
   Headers: Authorization: Bearer eyJhbGc...

   WSHandler.HandleConnections():
   ├─ Extrae userID del token -> 1 (Adoptante)
   ├─ Upgrade HTTP -> WebSocket
   ├─ Crea Client{userID: 1, ...}
   └─ Registra en Hub

                      │
                      ▼
2. Cargar Historial (HTTP GET)
   GET /api/v1/matches/1/messages

   SocialHandler.GetChatHistory():
   ├─ ChatService.GetHistory(matchID=1)
   ├─ SELECT * FROM messages WHERE match_id = 1 ORDER BY created_at ASC
   └─ Retorna [Message{id:1, ...}, Message{id:2, ...}]

   UI muestra conversación previa:
   ┌──────────────────────────┐
   │ Rescatista: "Hola soy   │ (id: 10, created_at: 2025-12-20)
   │ Maria, dueña de Max"    │
   │                          │
   │ Adoptante: "Hola Maria, │ (id: 11, created_at: 2025-12-20)
   │ cuánto pesa Max?"       │
   │                          │
   │ Rescatista: "Pesa 25kg" │ (id: 12, created_at: 2025-12-21)
   └──────────────────────────┘

                      │
                      ▼
3. Enviar Nuevo Mensaje (WebSocket)
   Client: {
       "match_id": 1,
       "content": "Eso es perfecto!"
   }

   WSHandler.HandleConnections() - Bucle:
   ├─ conn.ReadJSON(&req) -> {match_id: 1, content: "Eso es perfecto!"}
   ├─ chatService.SaveMessage(1, 1, "Eso es perfecto!")
   │  ├─ containsForbiddenContent("Eso es perfecto!") -> false (OK)
   │  ├─ GetMatch(1) -> status = "accepted" (OK)
   │  ├─ INSERT INTO messages (match_id, sender_id, content, created_at)
   │  │                VALUES (1, 1, "Eso es perfecto!", NOW())
   │  └─ Retorna Message{id: 13, match_id: 1, sender_id: 1, content: "..."}
   ├─ hub.broadcast <- "Eso es perfecto!" -> va a TODOS los conectados en ese match
   └─ Celular 2 (Rescatista) recibe en tiempo real

                      │
                      ▼
4. Rescatista recibe (WebSocket)
   hub.broadcast entrega a todos los clientes en ese match
   Celular 2 ve nuevo mensaje en tiempo real

   UI actualiza:
   ┌──────────────────────────┐
   │ ...                      │
   │ Adoptante: "Eso es      │ (id: 13, justo ahora)
   │ perfecto!"              │
   └──────────────────────────┘
```

## Sistema "Evil PAWS" (Filtro de Estafas)

### Objetivo

Proteger a adoptantes vulnerables de timadores. Un mal actor intenta:

- Solicitar depósito fuera de plataforma
- Pedir transferencia inmediata
- Amenazas ("Te mataré si no pagas")
- Odio explícito

**Solución**: Bloqueo silencioso en tiempo real.

### Palabras Clave Prohibidas

```go
var forbiddenWords = []string{
    "estafa",                  // Explícito
    "odio",                    // Amenaza de odio
    "matar",                   // Amenaza de violencia
    "depósito",                // Solicitud de pago fuera de plataforma
    "transferencia inmediata"  // Urgencia sospechosa
}
```

**Nota**: Esto es básico. En producción:

- Vendría de BD (actualizaciones dinámicas)
- Integraría NLP para detectar intent (no solo keywords)
- Usaría API externa (OpenAI GPT para clasificación)

### Flujo de Detección

```
┌──────────────────────────────────────────────────┐
│ Timador intenta enviar: "¿Me haces un depósito  │
│ y te devuelvo el dinero después de verificar?"  │
└──────────────┬──────────────────────────────────┘
               │
               ▼
conn.ReadJSON(&req) -> {match_id: 5, content: "...depósito..."}

                │
                ▼
chatService.SaveMessage(5, timadorID, "...depósito...")

    1. containsForbiddenContent("...depósito...")
       ├─ lowerText = "¿me haces un depósito..."
       ├─ Itera forbiddenWords
       ├─ "depósito" IN lowerText -> true
       └─ RETORNA: true (CONTIENE PALABRA PROHIBIDA)

    2. BLOQUEO
       if s.containsForbiddenContent(content) {
           return nil, errors.New("mensaje bloqueado...")
       }

    3. RESULTADO
       ├─ Mensaje NO se guarda en Postgres
       ├─ NO se difunde en Hub
       ├─ Cliente (timador) recibe error
       └─ Adoptante NUNCA VE el mensaje


┌──────────────────────────────────────────────────┐
│ Cliente (Timador)                                │
├──────────────────────────────────────────────────┤
│ errMsg := {"error": "Mensaje rechazado..."}      │
│                                                  │
│ Siente que su mensaje "se envió" pero el        │
│ servidor lo silenció. No sabe por qué.          │
│ Prueba otros ataques, eventualmente se rinde.   │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│ Cliente (Adoptante)                              │
├──────────────────────────────────────────────────┤
│ [Mensaje NUNCA aparece en su pantalla]           │
│                                                  │
│ Adoptante está protegido sin siquiera saberlo.  │
│ No ve la solicitud de estafa.                   │
└──────────────────────────────────────────────────┘
```

## Sistema de Reputación (Reviews)

### Modelo de Review

```
Review {
    ID: 1
    MatchID: 5          <--- Qué adopción
    AuthorID: 10        <--- Quién califica
    TargetID: 2         <--- A quién califica
    Rating: 4           <--- 1-5 estrellas
    Comment: "Llegó tarde pero fue amable"
    CreatedAt: 2025-12-21
}
```

### Lógica de AuthorID vs TargetID

**Caso 1: Adoptante Califica a Rescatista**

```
Match {
    AdopterID: 10    (Juan - Adoptante)
    PetID: 5         (Max - Mascota)
    Status: "accepted"
}

Pet { UserID: 2 }    (Maria - Rescatista)

Juan (10) crea review:
POST /reviews
{
    "match_id": 5,
    "rating": 5,
    "comment": "Maria es increíble, Max es perfecto"
}

ReviewService.CreateReview(5, 10, 5, "..."):
├─ Obtener Match(5) -> AdopterID = 10, PetID = 5
├─ Author = 10 == AdopterID? SI
├─ Por lo tanto, es adoptante calificando rescatista
├─ TargetID = Pet(5).UserID = 2 (Maria)
└─ Guardar Review{AuthorID: 10, TargetID: 2, Rating: 5, ...}

Resultado: Maria ahora tiene review de 5 estrellas
```

**Caso 2: Rescatista Califica a Adoptante**

```
Match { AdopterID: 10, PetID: 5 }
Pet { UserID: 2 }

Maria (2) crea review:
POST /reviews
{
    "match_id": 5,
    "rating": 4,
    "comment": "Juan cuida muy bien a Max, excelente"
}

ReviewService.CreateReview(5, 2, 4, "..."):
├─ Obtener Match(5) -> AdopterID = 10
├─ Author = 2 == AdopterID? NO
├─ Por lo tanto, es rescatista calificando adoptante
├─ TargetID = AdopterID = 10 (Juan)
└─ Guardar Review{AuthorID: 2, TargetID: 10, Rating: 4, ...}

Resultado: Juan ahora tiene review de 4 estrellas
```

### Flujo Completo de Adopción con Reviews

```
┌──────────────────────────────────────────────────────────────┐
│ FLUJO COMPLETO: De Perfil a Reputación                      │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
1. MATCHING (Fase 9)
   Juan completa perfil → GetSwipeDeck filtra mascotas
   Juan swipeea Max -> Match.status = "pending"
   Maria (rescatista) ve like -> Responde "accept"
   -> Match.status = "accepted"

                       │
                       ▼
2. CHAT PERSISTENTE (Fase 10)
   Juan conecta WebSocket -> GET /ws
   Carga historial -> GET /matches/5/messages -> vacío

   Juan: "Hola Maria, Max se ve increíble"
   ├─ SaveMessage(5, 10, "...") -> INSERT INTO messages
   ├─ containsForbiddenContent() -> false (OK)
   ├─ Match.status == "accepted" -> true (OK)
   └─ Hub.broadcast -> Maria lo recibe en tiempo real

                       │
                       ▼
3. INTERACCIÓN
   Juan: "Quiero conocer a Max mañana a las 10?"
   Maria: "Perfecto! Me veo en Parque Forestal"
   Juan: "Dale, hasta luego"
   Maria: "Listo, mucho gusto!"

   (10 mensajes se guardan en messages table con IDs 10-20)

                       │
                       ▼
4. ADOPCIÓN FINALIZADA
   Encuentro presencial transcurrió exitosamente
   Acuerdo legal cerrado (Fase 11 - Documento)
   Relación Match finalizada

                       │
                       ▼
5. REPUTACIÓN (Fase 10)
   Maria califica a Juan:
   POST /reviews
   {
       "match_id": 5,
       "rating": 5,
       "comment": "Hombre maravilloso, Max está en buenas manos"
   }

   ├─ ReviewService.CreateReview(5, 2, 5, "...")
   ├─ TargetID = 10 (Juan - Adoptante)
   ├─ INSERT INTO reviews
   └─ Juan ahora tiene 5 estrellas de María

                       │
                       ▼
6. REPUTACIÓN VISIBLE
   Otro rescatista (Carlos) ve perfil de Juan:
   ├─ SELECT AVG(rating) FROM reviews WHERE target_id = 10
   ├─ AVG = 5.0 (1 review de 5 estrellas)
   └─ Carlos piensa: "Este tipo es de confianza"

   Cuando Juan hace swipe a gato de Carlos:
   ├─ Carlos ve: "5.0 estrellas, María dice: 'Hombre maravilloso'"
   ├─ Carlos responde "accept" más fácilmente
   └─ Flujo de confianza construido por reputación
```

## Cambios en la Base de Datos

### Nuevas Tablas

#### messages

```sql
CREATE TABLE messages (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    match_id BIGINT NOT NULL,
    sender_id BIGINT NOT NULL,
    content LONGTEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    INDEX idx_match_id (match_id),
    INDEX idx_sender_id (sender_id),
    FOREIGN KEY (match_id) REFERENCES matches(id) ON DELETE CASCADE,
    FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
);
```

#### reviews

```sql
CREATE TABLE reviews (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    match_id BIGINT NOT NULL,
    author_id BIGINT NOT NULL,
    target_id BIGINT NOT NULL,
    rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment LONGTEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    INDEX idx_match_id (match_id),
    INDEX idx_author_id (author_id),
    INDEX idx_target_id (target_id),
    FOREIGN KEY (match_id) REFERENCES matches(id) ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (target_id) REFERENCES users(id) ON DELETE CASCADE
);
```

**Índices Críticos**:

- `match_id`: Para cargar historial rápidamente
- `target_id`: Para calcular reputación de un usuario

### Migraciones (main.go)

```go
database.DB.AutoMigrate(
    &domain.User{},
    &domain.BlacklistEntry{},
    &domain.Report{},
    &domain.UserProfile{},
    &domain.Pet{},
    &domain.Match{},
    &domain.Message{},      // NUEVO
    &domain.Review{},       // NUEVO
)
```

## Flujos de API

### 1. Conectar a Chat (WebSocket)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Conectar WebSocket con token
wscat -c "ws://localhost:8080/api/v1/ws" \
  -H "Authorization: Bearer $TOKEN"

# Una vez conectado, enviar mensaje JSON
> {
    "match_id": 5,
    "content": "Hola Maria, cómo estás?"
  }

# Recibir respuesta
< "Hola Juan, muy bien! Max está feliz"
```

### 2. Obtener Historial de Chat (HTTP GET)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/5/messages \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta (200 OK):

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
  },
  {
    "id": 12,
    "match_id": 5,
    "sender_id": 10,
    "content": "Mucho! Quiero conocerlo en persona",
    "is_read": true,
    "created_at": "2025-12-21T10:32:00Z"
  }
]
```

### 3. Crear Review (HTTP POST)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/reviews \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "match_id": 5,
    "rating": 5,
    "comment": "Maria es increíble, Max está perfecto"
  }'
```

Respuesta (201 Created):

```json
{ "message": "Reseña guardada" }
```

### 4. Ejemplo: Filtro "Evil PAWS" Bloqueando Mensaje

```bash
# Cliente (Timador) intenta enviar:
> {
    "match_id": 5,
    "content": "Hola, puedo hacer un depósito y luego confirmamos?"
  }

# Servidor detecta "depósito" en forbiddenWords
# Response (error sin guardar):
< {
    "error": "Mensaje rechazado: mensaje bloqueado por contener términos prohibidos o sospechosos"
  }

# Cliente (Adoptante) nunca ve el mensaje
# Postgres no tiene ningún registro del intento
```

## Decisiones Arquitectónicas

### 1. Chat Persistente vs Tubo Hueco

**Antes**: WebSocket sin BD = pérdida de mensajes

**Ahora**: SaveMessage en ChatService + Postgres = historial permanente

**Beneficio**: Recuperabilidad, auditoría, anti-repudio

### 2. Validación "Evil PAWS" Pasiva

No es "reportes" (Fase 8) que dependen de usuarios.

Es **pasivo**: El servidor bloquea automáticamente.

**Ventaja**: No requiere intervención, protege en tiempo real.

### 3. Rating 1-5 vs Binario

Podrían ser reportes binarios (Good/Bad).

Elegimos 1-5 para **nuances**:

- 5: Excelente
- 4: Bien
- 3: Normal
- 2: Problemas menores
- 1: Problemas graves

Permite reputación más precisa.

### 4. TargetID Automático en Reviews

No le pedimos al usuario "¿A quién calificar?".

ReviewService lo deduce del Match y roles.

**Simplifica UX** (menos inputs).

## Escalamiento Futuro (Roadmap)

### Typing Indicators

Mostrar "Maria está escribiendo..." en tiempo real.

Implementar con WebSocket eventos:

```json
{ "type": "typing", "user_id": 2 }
```

### Read Receipts

Marcar mensajes como leídos. Mostrar checkmarks.

```go
UPDATE messages SET is_read = true WHERE match_id = 5 AND id <= 12
```

### NLP para "Evil PAWS"

Cambiar de forbiddenWords a modelo ML.

Detectar intent de estafa, no solo keywords.

Integrar OpenAI GPT-4 para clasificación.

### Blocking User System

Adoptante puede bloquear a rescatista abusivo.

```go
type Block struct {
    BlockerID uint
    BlockedID uint
}
```

Impedir mensajes y matches futuros.
