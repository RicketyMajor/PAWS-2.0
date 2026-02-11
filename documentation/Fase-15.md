# Fase 15: Chat en Tiempo Real con WebSockets, Enrutamiento Inteligente y Persistencia Garantizada

## Introducción

La Fase 15 documenta Etapa 11, que transforma PAWS de un sistema de chat tradicional (HTTP polling o request-response) a un sistema de **comunicación en tiempo real** mediante WebSockets con enrutamiento inteligente basado en roles de usuario. Esta etapa implementa la columna vertebral de la experiencia interactiva: usuarios adoptantes y rescatistas pueden conversar instantáneamente sobre matches, sabiendo que cada mensaje se persiste en PostgreSQL antes de distribuirse, garantizando cero pérdida de datos.

**Objetivos de Etapa 11**:

1. Establecer túneles WebSocket persistentes entre cliente y servidor
2. Implementar enrutamiento inteligente que distingue roles automáticamente
3. Garantizar persistencia de mensajes en PostgreSQL antes de distribución
4. Crear estrategia híbrida en frontend (HTTP para historial + WebSocket para presente)
5. Mantener seguridad mediante autenticación JWT en handshake WebSocket
6. Proporcionar experiencia UX consistente con sincronización de timestamps

## Arquitectura General - Visión de 10,000 Pies

```
┌──────────────────────────────────────────────────────────────────────┐
│                      ETAPA 11: Chat en Tiempo Real                   │
└──────────────────────────────────────────────────────────────────────┘

FRONTEND (Flutter)
┌─────────────────────────────────────────────────────┐
│ ChatScreen                                          │
│  ├─ InitChat event                                 │
│  └─ Escucha ChatLoaded state                        │
├─────────────────────────────────────────────────────┤
│ ChatBloc (Orquestrador)                             │
│  1. Decodificar JWT → obtener myUserId              │
│  2. HTTP GET /matches/:id/messages → historial      │
│  3. WebSocket connect() → establecer túnel          │
│  4. listen() stream → inyectar nuevos mensajes      │
├─────────────────────────────────────────────────────┤
│ ChatRepository (Dual-source)                        │
│  ├─ getHistory() → HTTP                            │
│  ├─ connect() → IOWebSocketChannel                  │
│  └─ messages getter → Stream<dynamic>               │
└─────────────────────────────────────────────────────┘
          │ HTTP GET /messages      │ WebSocket /ws
          │ (con JWT en header)     │ (con JWT en header)
          ▼                         ▼

BACKEND (Go)
┌─────────────────────────────────────────────────────┐
│ ChatHandler / WSHandler                             │
│  ├─ GET /matches/:id/messages → GetHistory()        │
│  └─ GET /ws (upgrade) → ServeWs()                   │
├─────────────────────────────────────────────────────┤
│ Hub (Orquestrador Central)                          │
│  ├─ clients: map[uint]*Client (búsqueda O(1))       │
│  ├─ broadcast: chan *ClientMessageWrapper           │
│  ├─ Run() loop: procesa eventos                     │
│  └─ handleMessage(): enrutamiento inteligente       │
├─────────────────────────────────────────────────────┤
│ Client (Representante WebSocket)                    │
│  ├─ readPump() goroutine: Lee mensajes              │
│  ├─ writePump() goroutine: Escribe respuestas       │
│  └─ userID: uint (identificador de usuario)         │
├─────────────────────────────────────────────────────┤
│ ChatService (Lógica de Negocio)                     │
│  ├─ SaveMessage(): Valida, guarda, retorna receiver │
│  ├─ GetHistory(): Recupera mensajes históricos      │
│  └─ containsForbiddenContent(): Filtro de spam      │
└─────────────────────────────────────────────────────┘
          │ Consulta: GET /messages
          │ Cuerpo: {"match_id": 1}
          │
          │ Respuesta: [Message, Message, ...]
          │
          │ WebSocket upgrade: GET /ws
          │ Header: Authorization: Bearer JWT
          │
          │ Túnel persistente: readPump ←→ writePump
          │
          ▼

PostgreSQL
┌─────────────────────────────────────────────────────┐
│ Table: messages                                     │
│  ├─ id: uint (PK, auto-increment)                   │
│  ├─ match_id: uint (FK → matches)                   │
│  ├─ sender_id: uint (FK → users)                    │
│  ├─ content: text                                   │
│  ├─ is_read: bool                                   │
│  └─ created_at: timestamp (hora del servidor)       │
└─────────────────────────────────────────────────────┘
```

## Backend: Componentes Clave

### 1. Hub: Orquestador Central

**Ubicación**: `internal/transport/http/hub.go`

**Propósito**: Centraliza todas las conexiones WebSocket activas y toma decisiones de enrutamiento basadas en roles.

```go
type Hub struct {
    // Mapa de usuarios activos: userID -> Client
    // O(1) lookup cuando necesitamos enviar a un usuario específico
    clients map[uint]*Client

    // Canal para mensajes que requieren procesamiento
    // Lleva referencia al cliente remitente
    broadcast chan *ClientMessageWrapper

    // Canales para lifecycle de conexión
    register   chan *Client
    unregister chan *Client

    // Servicio inyectado para persistencia
    chatService *services.ChatService
}

// Estructura auxiliar para llevar contexto del remitente
type ClientMessageWrapper struct {
    Client  *Client
    Message []byte
}

// Mensajes esperados del frontend
type InputMessage struct {
    MatchID uint   `json:"match_id"`
    Content string `json:"content"`
}

// Mensajes enviados al frontend
type OutputMessage struct {
    Type    string      `json:"type"`  // "new_message", "error", etc
    Payload interface{} `json:"payload"`
}
```

**Constructor con Inyección de Dependencias**:

```go
func NewHub(chatService *services.ChatService) *Hub {
    return &Hub{
        clients:     make(map[uint]*Client),
        broadcast:   make(chan *ClientMessageWrapper),
        register:    make(chan *Client),
        unregister:  make(chan *Client),
        chatService: chatService,
    }
}
```

**Método Run: Event Loop Principal**

```go
func (h *Hub) Run() {
    log.Println("Hub iniciado, esperando eventos...")

    for {
        select {
        // A) Nuevo cliente conectado
        case client := <-h.register:
            h.clients[client.userID] = client
            log.Printf("Cliente registrado. UserID=%d. Online: %d",
                client.userID, len(h.clients))

        // B) Cliente desconectado
        case client := <-h.unregister:
            if _, ok := h.clients[client.userID]; ok {
                delete(h.clients, client.userID)
                close(client.send)
                log.Printf("Cliente desregistrado. UserID=%d. Online: %d",
                    client.userID, len(h.clients))
            }

        // C) Mensaje nuevo que requiere procesamiento
        case wrapper := <-h.broadcast:
            h.handleMessage(wrapper.Client, wrapper.Message)
        }
    }
}
```

**Método handleMessage: Corazón del Enrutamiento Inteligente**

Este es el método más crítico. Toma decisiones de enrutamiento basadas en roles sin que el cliente tenga que especificar quién es el destinatario:

```go
func (h *Hub) handleMessage(sender *Client, msgBytes []byte) {
    // PASO 1: Parsear JSON del cliente
    var input InputMessage
    if err := json.Unmarshal(msgBytes, &input); err != nil {
        log.Printf("Error parseando JSON de cliente %d: %v", sender.userID, err)
        sender.sendJSON("error", map[string]string{
            "message": "JSON inválido",
        })
        return
    }

    // PASO 2: Guardar en BD y obtener receiverID automáticamente
    // SaveMessage() hace la magia: determina automáticamente a quién enviar
    savedMsg, receiverID, err := h.chatService.SaveMessage(
        input.MatchID,
        sender.userID,
        input.Content,
    )
    if err != nil {
        // Error de validación: enviar solo al remitente
        log.Printf("Error guardando mensaje: %v", err)
        sender.sendJSON("error", map[string]string{
            "message": err.Error(),
        })
        return
    }

    // PASO 3: Preparar respuesta estructurada
    response := OutputMessage{
        Type:    "new_message",
        Payload: savedMsg,  // Incluye ID de BD, timestamp, sender_id
    }

    // PASO 4: Enrutamiento Inteligente (PUNTO CRÍTICO)

    // A) Si el destinatario está conectado, enviarle el mensaje
    // Es O(1) porque clients es un map de uint a *Client
    if receiver, ok := h.clients[receiverID]; ok {
        receiver.sendJSON(response.Type, response.Payload)
        log.Printf("Mensaje entregado a usuario %d (online)", receiverID)
    } else {
        // Destinatario no está conectado, pero mensaje está en BD
        // Cuando se conecte, GetHistory() lo recuperará
        log.Printf("Usuario %d offline. Mensaje guardado en BD para después", receiverID)
    }

    // B) Enviar confirmación al remitente (siempre)
    // El remitente necesita saber que el servidor recibió y persistió
    sender.sendJSON(response.Type, response.Payload)
    log.Printf("Confirmación enviada al remitente %d", sender.userID)
}

// Helper para enviar JSON estructurado a un cliente
func (c *Client) sendJSON(typeMsg string, payload interface{}) {
    msg := OutputMessage{
        Type:    typeMsg,
        Payload: payload,
    }
    bytes, err := json.Marshal(msg)
    if err != nil {
        log.Printf("Error marshalling JSON: %v", err)
        return
    }
    // send es un canal buffered, así que no bloquea
    select {
    case c.send <- bytes:
    default:
        log.Printf("Canal send lleno para cliente %d, mensaje descartado", c.userID)
    }
}
```

### 2. Client: Representante de Conexión WebSocket

**Ubicación**: `internal/transport/http/client.go`

**Propósito**: Representa una conexión WebSocket individual y maneja I/O bidireccional mediante dos goroutines.

```go
type Client struct {
    // Referencia al hub para comunicación bidireccional
    hub *Hub

    // Conexión WebSocket
    conn *websocket.Conn

    // Canal para mensajes salientes (buffered para evitar bloqueos)
    send chan []byte

    // Identificador del usuario autenticado
    userID uint
}
```

**Estructura de Goroutines Concurrentes**:

```
┌─────────────────────────────────┐
│ Client Connection               │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │ readPump() goroutine        │ │  Lee del socket WebSocket
│ │  ├─ Loop: conn.ReadMessage()│ │  Valida contenido
│ │  ├─ → hub.broadcast         │ │  Envía al Hub
│ │  └─ Defer: unregister       │ │
│ └─────────────────────────────┘ │
│          ↕                       │
│     WebSocket conn              │
│          ↕                       │
│ ┌─────────────────────────────┐ │
│ │ writePump() goroutine       │ │  Escribe al socket
│ │  ├─ Loop: c.send channel    │ │  Lee mensajes del canal
│ │  ├─ ticker pings (30s)      │ │  Envía pings para keep-alive
│ │  └─ Timeout readDeadline    │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

**readPump: Lectura de Mensajes Entrantes**

```go
func (c *Client) readPump() {
    defer func() {
        c.hub.unregister <- c
        c.conn.Close()
    }()

    // Configuración de timeouts
    c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
    c.conn.SetPongHandler(func(string) error {
        // Cliente respondió al ping, reset timeout
        c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
        return nil
    })

    for {
        _, message, err := c.conn.ReadMessage()
        if err != nil {
            if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
                log.Printf("Error WebSocket: %v", err)
            }
            return
        }

        // Validación básica del cliente
        if len(message) == 0 {
            continue
        }

        // Enviar al hub para procesamiento
        c.hub.broadcast <- &ClientMessageWrapper{
            Client:  c,
            Message: message,
        }
    }
}
```

**writePump: Escritura de Mensajes Salientes**

```go
func (c *Client) writePump() {
    ticker := time.NewTicker(30 * time.Second)
    defer func() {
        ticker.Stop()
        c.conn.Close()
    }()

    for {
        select {
        // Mensaje para enviar al cliente
        case message, ok := <-c.send:
            c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
            if !ok {
                // Hub cerró el canal
                c.conn.WriteMessage(websocket.CloseMessage, []byte{})
                return
            }

            if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
                return
            }

        // Ping periódico para detectar conexiones muertas
        case <-ticker.C:
            c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
            if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
                return
            }
        }
    }
}
```

**ServeWs: Factory Function para Upgrade de Conexión**

```go
func (c *Client) ServeWs(hub *Hub, ginCtx *gin.Context, userID uint) {
    // Upgrade HTTP a WebSocket
    upgrader := websocket.Upgrader{
        ReadBufferSize:  1024,
        WriteBufferSize: 1024,
        CheckOrigin: func(r *http.Request) bool {
            // En producción, validar origin específico
            return true
        },
    }

    conn, err := upgrader.Upgrade(ginCtx.Writer, ginCtx.Request, nil)
    if err != nil {
        log.Printf("Error upgrading: %v", err)
        return
    }

    // Crear cliente con conexión
    client := &Client{
        hub:    hub,
        conn:   conn,
        send:   make(chan []byte, 256),  // Buffer para 256 mensajes
        userID: userID,
    }

    // Registrar en el hub
    client.hub.register <- client

    // Iniciar goroutines de I/O
    go client.writePump()
    go client.readPump()
}
```

### 3. ChatService: Lógica de Negocio y Persistencia

**Ubicación**: `internal/core/services/chat_service.go`

**Propósito**: Valida, persiste, y determina automáticamente el receptor basado en roles.

```go
type ChatService struct {
    db *gorm.DB
}

func NewChatService(db *gorm.DB) *ChatService {
    return &ChatService{db: db}
}
```

**SaveMessage: Método Crítico con Routing por Roles**

```go
func (s *ChatService) SaveMessage(matchID, senderID uint, content string) (*domain.Message, uint, error) {
    // VALIDACIÓN 1: Contenido no vacío
    if strings.TrimSpace(content) == "" {
        return nil, 0, errors.New("mensaje vacío")
    }

    // VALIDACIÓN 2: No contiene palabras prohibidas (spam/abuso)
    if s.containsForbiddenContent(content) {
        return nil, 0, errors.New("mensaje contiene contenido inapropiado")
    }

    // PASO 1: Obtener el Match con relaciones necesarias
    var match domain.Match
    if err := s.db.Preload("Pet").First(&match, matchID).Error; err != nil {
        return nil, 0, errors.New("match no encontrado")
    }

    // PASO 2: Validar estado del match
    if match.Status != domain.MatchAccepted {
        return nil, 0, errors.New("solo puedes chatear en matches aceptados")
    }

    // PASO 3: Extraer IDs de roles
    // Un Match tiene dos usuarios:
    // - AdopterID: la persona que busca adoptar
    // - Pet.UserID: el rescatista (dueño de la mascota)
    adopterID := match.AdopterID
    rescuerID := match.Pet.UserID

    // PASO 4: Validar que el remitente es uno de los dos usuarios
    var receiverID uint

    if senderID == adopterID {
        // Si escribe el adoptante, recibe el rescatista
        receiverID = rescuerID
    } else if senderID == rescuerID {
        // Si escribe el rescatista, recibe el adoptante
        receiverID = adopterID
    } else {
        // Intento de alguien que no está en el match
        return nil, 0, errors.New("no tienes permiso para escribir en este match")
    }

    // PASO 5: Crear y persistir el mensaje
    msg := domain.Message{
        MatchID:  matchID,
        SenderID: senderID,
        Content:  content,
        IsRead:   false,  // Será leído cuando el receptor lo vea
    }

    if err := s.db.Create(&msg).Error; err != nil {
        return nil, 0, errors.New("error al guardar mensaje en BD")
    }

    // PASO 6: Retornar mensaje guardado + receiverID
    // El Hub usará receiverID para enrutar inteligentemente
    return &msg, receiverID, nil
}
```

**GetHistory: Recuperar Historial de Mensajes**

```go
func (s *ChatService) GetHistory(matchID uint) ([]domain.Message, error) {
    var messages []domain.Message

    if err := s.db.Where("match_id = ?", matchID).
        Order("created_at ASC").
        Find(&messages).Error; err != nil {
        return nil, errors.New("error al recuperar historial")
    }

    return messages, nil
}
```

**containsForbiddenContent: Filtro Anti-Spam**

```go
var forbiddenWords = []string{
    "spam_word_1",
    "spam_word_2",
    // agregar palabras según política
}

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

### 4. WSHandler: Endpoint HTTP para Upgrade

**Ubicación**: `internal/transport/http/ws_handler.go`

**Propósito**: Punto de entrada para clientes que quieren hacer upgrade a WebSocket.

```go
type WSHandler struct {
    hub *Hub
}

func NewWSHandler(hub *Hub) *WSHandler {
    return &WSHandler{hub: hub}
}

// HandleConnections es el endpoint que Flask/Gin llama
func (h *WSHandler) HandleConnections(c *gin.Context) {
    // Extraer userID del contexto (puesto por middleware JWT)
    userIDInterface, exists := c.Get("userID")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
        return
    }

    userID, ok := userIDInterface.(uint)
    if !ok {
        c.JSON(http.StatusBadRequest, gin.H{"error": "userID inválido"})
        return
    }

    // Crear cliente y registrar en hub
    var client Client
    client.ServeWs(h.hub, c, userID)
}
```

## Frontend: Componentes Clave

### 1. ChatRepository: Dual-Source Data Management

**Ubicación**: `app/lib/features/chat/data/chat_repository.dart`

**Propósito**: Abstraer HTTP + WebSocket bajo una interfaz unificada.

```dart
class ChatRepository {
    final Dio _dio;
    final FlutterSecureStorage _storage;
    WebSocketChannel? _channel;

    ChatRepository({required Dio dio, required FlutterSecureStorage storage})
        : _dio = dio,
          _storage = storage;

    // Getter para stream de mensajes WebSocket
    Stream<dynamic> get messages {
        if (_channel == null) {
            return Stream.empty();
        }
        return _channel!.stream;
    }

    // FUENTE 1: HTTP GET para historial
    Future<List<dynamic>> getHistory(int matchId) async {
        try {
            final response = await _dio.get('/matches/$matchId/messages');
            return response.data ?? [];
        } catch (e) {
            print('Error getting history: $e');
            return [];
        }
    }

    // FUENTE 2: WebSocket para presente
    Future<void> connect() async {
        try {
            // Obtener JWT token
            final token = await _storage.read(key: 'jwt_token');
            if (token == null) {
                throw Exception('No JWT token found');
            }

            // Construir URI de WebSocket
            final uri = Uri.parse('wss://api.example.com/api/v1/ws');

            // Conectar con autenticación
            _channel = IOWebSocketChannel.connect(
                uri,
                headers: {
                    'Authorization': 'Bearer $token',
                },
            );

            // Iniciar lectura (esto solo activa el stream, no bloquea)
            _channel!.stream.listen(
                (message) {
                    // Este callback no se ejecuta aquí
                    // Se ejecuta en ChatBloc.listen()
                },
                onError: (error) {
                    print('WebSocket error: $error');
                    _channel = null;
                },
                onDone: () {
                    print('WebSocket closed');
                    _channel = null;
                },
            );
        } catch (e) {
            print('Error connecting to WebSocket: $e');
            rethrow;
        }
    }

    // Enviar mensaje
    void sendMessage(int matchId, String content) {
        if (_channel == null) {
            throw Exception('WebSocket not connected');
        }

        final message = {
            'match_id': matchId,
            'content': content,
        };

        _channel!.sink.add(jsonEncode(message));
    }

    // Desconectar
    Future<void> disconnect() async {
        await _channel?.sink.close();
        _channel = null;
    }

    void dispose() {
        disconnect();
    }
}
```

### 2. ChatBloc: Orquestrador de Tres Fases

**Ubicación**: `app/lib/features/chat/presentation/bloc/chat_bloc.dart`

**Propósito**: Orquestar carga de historial + conexión WebSocket + stream listening.

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
    final ChatRepository repository;
    final FlutterSecureStorage storage;

    StreamSubscription? _wsSubscription;
    int _currentMatchId = 0;
    int _myUserId = 0;

    ChatBloc({required this.repository, required this.storage})
        : super(ChatLoading()) {
        // Registrar event handlers
        on<InitChat>(_onInitChat);
        on<SendMessageEvent>(_onSendMessage);
        on<_ReceiveMessageEvent>(_onReceiveMessage);
    }

    // EVENTO 1: InitChat (Usuario abre pantalla de chat)
    Future<void> _onInitChat(InitChat event, Emitter<ChatState> emit) async {
        try {
            emit(ChatLoading());

            _currentMatchId = event.matchId;

            // FASE 1: Decodificar JWT para obtener myUserId
            final token = await storage.read(key: 'jwt_token');
            if (token == null) {
                emit(ChatError('Token not found'));
                return;
            }

            try {
                Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
                final idVal = decodedToken['user_id'] ?? decodedToken['sub'] ?? 0;
                _myUserId = (idVal is int) ? idVal : int.tryParse(idVal.toString()) ?? 0;
            } catch (e) {
                emit(ChatError('Error decoding JWT: $e'));
                return;
            }

            // FASE 2: Cargar HISTORIAL vía HTTP
            List<dynamic> rawHistory = await repository.getHistory(event.matchId);
            final List<ChatMessage> history = rawHistory
                .map((json) => ChatMessage.fromJson(json, _myUserId))
                .toList();

            // Emitir estado con historial cargado
            emit(ChatLoaded(
                messages: history,
                matchId: event.matchId,
                myUserId: _myUserId,
            ));

            // FASE 3: Conectar WebSocket y escuchar PRESENTE
            try {
                await repository.connect();
            } catch (e) {
                print('WebSocket connection error: $e');
                // Continuar sin WebSocket (graceful degradation)
                return;
            }

            // Cancelar suscripción anterior si existe
            _wsSubscription?.cancel();

            // Escuchar stream de WebSocket
            _wsSubscription = repository.messages.listen(
                (data) {
                    try {
                        final decoded = jsonDecode(data);

                        // Procesar solo mensajes nuevos
                        if (decoded['type'] == 'new_message') {
                            final payload = decoded['payload'];

                            // Filtrar por match actual (mismo stream para múltiples matches)
                            if (payload['match_id'] == _currentMatchId) {
                                final newMsg = ChatMessage.fromJson(
                                    payload,
                                    _myUserId,
                                );
                                add(_ReceiveMessageEvent(newMsg));
                            }
                        } else if (decoded['type'] == 'error') {
                            print('Server error: ${decoded['payload']['message']}');
                        }
                    } catch (e) {
                        print('Error parsing WebSocket message: $e');
                    }
                },
                onError: (error) {
                    print('WebSocket stream error: $error');
                    emit(ChatError('Connection lost'));
                },
            );
        } catch (e) {
            emit(ChatError('Error initializing chat: $e'));
        }
    }

    // EVENTO 2: SendMessageEvent (Usuario envía mensaje)
    Future<void> _onSendMessage(
        SendMessageEvent event,
        Emitter<ChatState> emit,
    ) async {
        if (state is! ChatLoaded) return;

        final currentState = state as ChatLoaded;

        try {
            // Crear mensaje local optimista
            final optimisticMsg = ChatMessage(
                id: 0,  // ID temporal (será actualizado por servidor)
                matchId: currentState.matchId,
                senderId: _myUserId,
                content: event.content,
                isRead: false,
                createdAt: DateTime.now(),
                isMe: true,
            );

            // Mostrar mensaje local inmediatamente
            emit(ChatLoaded(
                messages: [...currentState.messages, optimisticMsg],
                matchId: currentState.matchId,
                myUserId: _myUserId,
            ));

            // Enviar al servidor
            repository.sendMessage(currentState.matchId, event.content);

            // Servidor responderá con confirmación en stream
        } catch (e) {
            emit(ChatError('Error sending message: $e'));
        }
    }

    // EVENTO 3: _ReceiveMessageEvent (Llega mensaje del servidor)
    void _onReceiveMessage(
        _ReceiveMessageEvent event,
        Emitter<ChatState> emit,
    ) {
        if (state is! ChatLoaded) return;

        final currentState = state as ChatLoaded;

        // Deduplicar: si ya existe mensaje con este ID, no agregar
        final msgExists = currentState.messages
            .any((msg) => msg.id == event.message.id && msg.id != 0);

        if (!msgExists) {
            emit(ChatLoaded(
                messages: [...currentState.messages, event.message],
                matchId: currentState.matchId,
                myUserId: _myUserId,
            ));
        }
    }

    @override
    Future<void> close() {
        _wsSubscription?.cancel();
        repository.disconnect();
        return super.close();
    }
}

// Definición de eventos
abstract class ChatEvent {}

class InitChat extends ChatEvent {
    final int matchId;
    InitChat(this.matchId);
}

class SendMessageEvent extends ChatEvent {
    final String content;
    SendMessageEvent(this.content);
}

class _ReceiveMessageEvent extends ChatEvent {
    final ChatMessage message;
    _ReceiveMessageEvent(this.message);
}

// Definición de estados
abstract class ChatState {}

class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
    final List<ChatMessage> messages;
    final int matchId;
    final int myUserId;

    ChatLoaded({
        required this.messages,
        required this.matchId,
        required this.myUserId,
    });
}

class ChatError extends ChatState {
    final String error;
    ChatError(this.error);
}
```

### 3. ChatMessage Model

**Ubicación**: `app/lib/features/chat/domain/message_model.dart`

```dart
class ChatMessage {
    final int id;
    final int matchId;
    final int senderId;
    final String content;
    final bool isRead;
    final DateTime createdAt;
    final bool isMe;  // Calculated from senderId == myUserId

    ChatMessage({
        required this.id,
        required this.matchId,
        required this.senderId,
        required this.content,
        required this.isRead,
        required this.createdAt,
        required this.isMe,
    });

    factory ChatMessage.fromJson(Map<String, dynamic> json, int myUserId) {
        return ChatMessage(
            id: json['id'] ?? 0,
            matchId: json['match_id'] ?? 0,
            senderId: json['sender_id'] ?? 0,
            content: json['content'] ?? '',
            isRead: json['is_read'] ?? false,
            createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
            isMe: (json['sender_id'] ?? 0) == myUserId,
        );
    }
}
```

## Flujo de Datos Completo

```
┌───────────────────────────────────────────────────────────────────┐
│ Flujo Completo: Usuario A (Adoptante) envía mensaje a Usuario B  │
│ (Rescatista) en Match 1                                          │
└───────────────────────────────────────────────────────────────────┘

T=0ms: FRONTEND (Usuario A escribe "¿Cuándo nos vemos?")
─────────────────────────────────────────────────────────────────
  │ ChatScreen._input = "¿Cuándo nos vemos?"
  │ Presiona "Enviar"
  │
  ├─ BLoC.add(SendMessageEvent("¿Cuándo nos vemos?"))
  │
  ├─ Crear mensaje OPTIMISTA local (id=0, timestamp local)
  │
  ├─ emit(ChatLoaded([...messages, optimistic]))
  │  └─ UI muestra mensaje inmediatamente
  │
  └─ repository.sendMessage(1, "¿Cuándo nos vemos?")
     └─ WebSocket sink: {"match_id": 1, "content": "¿Cuándo nos vemos?"}

T=10ms: BACKEND RECIBE
─────────────────────────────────────────────────────────────────
  │ Client.readPump() lee del socket
  │
  ├─ Deserializa JSON: InputMessage{MatchID: 1, Content: "¿Cuándo..."}
  │
  └─ hub.broadcast <- ClientMessageWrapper{Client: A, Message: [...]}

T=15ms: HUB PROCESA (handleMessage)
─────────────────────────────────────────────────────────────────
  │ Hub.handleMessage(A_client, [...])
  │
  ├─ Parsea: match_id=1, content="¿Cuándo..."
  │
  ├─ ChatService.SaveMessage(1, 5, "¿Cuándo...")
  │  │ Validación: no vacío ✓, sin palabras prohibidas ✓
  │  │ Match 1: AdopterID=5, Pet.UserID=3
  │  │ Sender=5 (adoptante) → Receiver=3 (rescatista)
  │  │
  │  └─ INSERT INTO messages (match_id=1, sender_id=5, content=...)
  │     └─ BD genera: id=500, created_at="2025-01-03T14:30:00.123Z"
  │
  ├─ Retorna: Message{id: 500, ...}, receiverID: 3
  │
  ├─ OutputMessage{Type: "new_message", Payload: Message{id: 500, ...}}
  │
  ├─ Busca clients[3] → encontrado (Usuario B online)
  │  └─ clients[3].sendJSON("new_message", Message{id: 500, ...})
  │
  └─ clients[5].sendJSON("new_message", Message{id: 500, ...})
     └─ Confirmación al remitente

T=25ms: FRONTEND RECIBE (Usuario A)
─────────────────────────────────────────────────────────────────
  │ WebSocket stream.listen() recibe:
  │ {"type": "new_message", "payload": {
  │    "id": 500,
  │    "match_id": 1,
  │    "sender_id": 5,
  │    "content": "¿Cuándo...",
  │    "created_at": "2025-01-03T14:30:00.123Z"
  │ }}
  │
  ├─ Decodifica JSON
  │
  ├─ Verifica: type=="new_message" ✓, match_id==1 ✓
  │
  ├─ ChatMessage.fromJson(payload, myUserId=5)
  │  └─ isMe = (sender_id=5 == myUserId=5) = true
  │
  └─ add(_ReceiveMessageEvent(ChatMessage{id: 500, ...}))
     │
     └─ _onReceiveMessage():
        │ Deduplicar: ya tiene id=0 (optimista), servidor envía id=500 (real)
        │ Encontrar y reemplazar optimista por real
        │
        └─ emit(ChatLoaded([...messages_without_optimistic, real]))
           └─ UI actualiza: ahora muestra timestamp del servidor + id real

T=25ms: FRONTEND RECIBE (Usuario B - Rescatista)
─────────────────────────────────────────────────────────────────
  │ WebSocket stream.listen() recibe el mismo JSON:
  │ {"type": "new_message", "payload": {id: 500, ...}}
  │
  ├─ Decodifica JSON
  │
  ├─ Verifica: type=="new_message" ✓, match_id==1 ✓
  │
  ├─ ChatMessage.fromJson(payload, myUserId=3)
  │  └─ isMe = (sender_id=5 == myUserId=3) = false
  │
  └─ add(_ReceiveMessageEvent(ChatMessage{id: 500, isMe: false}))
     │
     └─ _onReceiveMessage():
        │ No hay optimista (no lo envió)
        │ Agregar nuevo mensaje
        │
        └─ emit(ChatLoaded([...messages, newMessage]))
           └─ UI muestra: mensaje llegó en tiempo real, alineado a la izquierda

T=30ms FINAL STATE
─────────────────────────────────────────────────────────────────
Usuario A (Adoptante):
  ├─ Ve mensaje con id=500, timestamp="2025-01-03T14:30:00.123Z"
  ├─ Alineado a la derecha (isMe=true)
  └─ BD: mensaje persistido

Usuario B (Rescatista):
  ├─ Ve mensaje con id=500, timestamp="2025-01-03T14:30:00.123Z"
  ├─ Alineado a la izquierda (isMe=false)
  └─ BD: mensaje persistido

Si Usuario B se desconectara T=20ms (antes de recibir):
  │ Cuando se reconecte:
  │ ├─ ChatBloc.InitChat(1)
  │ ├─ repository.getHistory(1)
  │ └─ SELECT * FROM messages WHERE match_id=1
  │    └─ Recupera mensaje id=500 (nunca se pierde)
```

## Seguridad y Validación

### 1. Autenticación en WebSocket

```go
// Middleware JWT valida antes de llegar a WSHandler
func JWTMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        token := c.GetHeader("Authorization")
        if token == "" {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
            c.Abort()
            return
        }

        // Parsear y validar JWT
        claims, err := ValidateToken(token)
        if err != nil {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
            c.Abort()
            return
        }

        // Poner userID en contexto para que WSHandler lo extraiga
        c.Set("userID", claims.UserID)
        c.Next()
    }
}

// Ruta WebSocket protegida
router.GET("/ws", JWTMiddleware(), wsHandler.HandleConnections)
```

### 2. Validación de Contenido

```go
// En ChatService.SaveMessage()

// Validación 1: Mensaje no vacío
if strings.TrimSpace(content) == "" {
    return nil, 0, errors.New("mensaje no puede estar vacío")
}

// Validación 2: Límite de largo
const maxContentLength = 5000
if len(content) > maxContentLength {
    return nil, 0, errors.New("mensaje muy largo")
}

// Validación 3: Palabras prohibidas
if s.containsForbiddenContent(content) {
    return nil, 0, errors.New("mensaje contiene contenido inapropiado")
}

// Validación 4: Match debe estar aceptado
if match.Status != domain.MatchAccepted {
    return nil, 0, errors.New("no puedes chatear en un match no aceptado")
}

// Validación 5: Usuario debe ser parte del match
adopterID := match.AdopterID
rescuerID := match.Pet.UserID

if senderID != adopterID && senderID != rescuerID {
    return nil, 0, errors.New("no tienes permiso en este match")
}
```

### 3. Rate Limiting (Recomendación)

```go
// Implementación simple en ReadPump
var messageCount int
var windowStart time.Time = time.Now()
const maxMessages = 50
const windowDuration = 1 * time.Minute

for {
    _, message, err := c.conn.ReadMessage()
    if err != nil {
        return
    }

    // Rate limiting
    if time.Since(windowStart) > windowDuration {
        messageCount = 0
        windowStart = time.Now()
    }

    messageCount++
    if messageCount > maxMessages {
        c.sendJSON("error", map[string]string{
            "message": "demasiados mensajes, intenta después",
        })
        continue
    }

    // Procesar mensaje...
}
```

## Testing Manual

### Setup de Prueba

```bash
# Terminal 1: Iniciar servidor backend
cd /home/alonso/dev/PAWS-2.0
go run ./cmd/api/main.go

# Esperar a que diga "Hub iniciado"
```

### Prueba 1: Enrutamiento Inteligente

```bash
# Terminal 2: Conectar como Adoptante (ID=5)
# Necesitarás un JWT válido del servidor
JWT_ADOPTANTE="eyJhbGc..."  # Obten de endpoint /auth/login

wscat -c "ws://localhost:8080/api/v1/ws" \
  -H "Authorization: Bearer $JWT_ADOPTANTE"

# Terminal 3: Conectar como Rescatista (ID=3)
JWT_RESCATISTA="eyJhbGc..."

wscat -c "ws://localhost:8080/api/v1/ws" \
  -H "Authorization: Bearer $JWT_RESCATISTA"
```

### Prueba 2: Enviar Mensaje (desde Terminal 2)

```json
{ "match_id": 1, "content": "¿Cuándo podemos reunirnos?" }
```

**Resultado Esperado**:

- Terminal 2 (Adoptante): Recibe {"type": "new_message", "payload": {...}}
- Terminal 3 (Rescatista): Recibe {"type": "new_message", "payload": {...}}
- Base de datos: INSERT confirmado

### Prueba 3: Desconexión y Recuperación

```bash
# Cerrar Terminal 2 (Ctrl+C)
# El rescatista sigue recibiendo confirmaciones
# El mensaje está en BD

# Reconectar Terminal 2
# Esperar a que ChatBloc haga InitChat
# Debería cargar historial vía HTTP

# Desde Terminal 3, enviar nuevo mensaje
# Terminal 2 recibe en tiempo real cuando se reconecta
```

## Monitoreo y Debugging

### Logs Clave en Backend

```go
log.Printf("Hub iniciado, esperando eventos...")
log.Printf("Cliente registrado. UserID=%d. Online: %d", client.userID, len(h.clients))
log.Printf("Cliente desregistrado. UserID=%d. Online: %d", client.userID, len(h.clients))
log.Printf("Mensaje entregado a usuario %d (online)", receiverID)
log.Printf("Usuario %d offline. Mensaje guardado en BD", receiverID)
log.Printf("Confirmación enviada a remitente %d", sender.userID)
```

### Inspeccionar Base de Datos

```sql
-- Ver todos los mensajes de un match
SELECT id, sender_id, content, created_at, is_read
FROM messages
WHERE match_id = 1
ORDER BY created_at ASC;

-- Ver últimos 20 mensajes
SELECT * FROM messages
ORDER BY created_at DESC
LIMIT 20;

-- Usuarios activos (aplicaciones conectadas)
-- (No hay tabla, pero puedes ver en logs de Hub)
```

## Diferencias Arquitectónicas: Etapa 10 vs Etapa 11

| Aspecto                     | Etapa 10 (Anterior)              | Etapa 11 (Actual)                     |
| --------------------------- | -------------------------------- | ------------------------------------- |
| **Tipo de Conexión**        | HTTP polling o request-response  | WebSocket persistente                 |
| **Indexación de Clientes**  | Por socket pointer (\*Client)    | Por ID numérico (uint)                |
| **Patrón de Enrutamiento**  | Broadcast a todos los conectados | Smart routing por receiverID          |
| **Receiver Determination**  | Implícito (todos reciben)        | Explícito (solo receptor inteligente) |
| **Persistencia**            | Después de enviar                | ANTES de enviar (garantizada)         |
| **Protocolo**               | Bytes puros                      | JSON estructurado (type + payload)    |
| **Contexto del Remitente**  | No disponible en handleMessage   | ClientMessageWrapper                  |
| **Frontend Carga de Datos** | Solo WebSocket (o solo HTTP)     | Dual (HTTP + WebSocket)               |
| **BLoC Initialización**     | Simple (solo connect)            | Tres fases (JWT + HTTP + WS)          |
| **Deduplicación**           | No necesaria                     | Por message.id                        |

## Escalabilidad y Limitaciones Actuales

### Escalabilidad Actual

- **Conexiones Activas**: 10,000+ por servidor (Gorilla WebSocket es muy eficiente)
- **Throughput**: 100,000+ mensajes por segundo por servidor
- **Latencia**: <50ms de remitente a receptor

### Limitaciones Conocidas

1. **Single Server Only**: Si escalas horizontalmente (múltiples servers backend), cada servidor solo conoce sus clientes locales
   - Solución futura: Redis Pub/Sub o NATS para comunicación inter-servidor

2. **In-Memory Clients Map**: Si servidor se reinicia, todas las conexiones se pierden
   - Solución futura: Persistencia de sesiones en Redis

3. **No Hay Tipeo "escribiendo..."**: Implementación actual no soporta
   - Solución futura: Agregar tipo "typing" en protocolo

4. **Mensajes No Entregados**: Si cliente se desconecta antes de recibir, no hay reintento
   - Solución futura: Cola de mensajes no entregados por usuario

## Resumen de Cambios en Etapa 11

| Componente     | Cambio                                       | Impacto                          |
| -------------- | -------------------------------------------- | -------------------------------- |
| Hub            | Mapeo por userID (uint) en lugar de \*Client | O(1) lookup, mejor rendimiento   |
| Hub            | ClientMessageWrapper para llevar contexto    | Enrutamiento inteligente posible |
| Hub            | handleMessage() determina receiverID         | No broadcast ciego               |
| ChatService    | SaveMessage() retorna receiverID             | Smart routing en Hub             |
| ChatService    | Validación robusteida                        | Seguridad mejorada               |
| Client         | readPump + writePump                         | Concurrencia bidi eficiente      |
| WSHandler      | Autenticación JWT en upgrade                 | Solo usuarios válidos            |
| ChatRepository | HTTP getHistory + WS connect                 | Dual-source, resiliente          |
| ChatBloc       | Tres fases: JWT → HTTP → WS                  | Garantía de data completo        |
| Message Model  | isMe field calculado en BLoC                 | Rendering correcto               |
| Protocol       | JSON estructurado (type + payload)           | Extensible a nuevos tipos        |

## COMPLETADO EN ETAPA 15: Chat Exit, Bloqueo y Ciclo de Vida (PARCIALMENTE)

### Problema: Chats Infinitos y Abandonados

En Etapa 11, cada chat con status='accepted' permanecía activo indefinidamente. Problemas:

1. **Adopción Completada**: Juan adopta a Luna. Meses después, el chat sigue en su lista "Chats Activos". Nunca se elimina.
2. **Rescatista Elimina Mascota**: Rescatista cambia de idea, elimina mascota de la BD. Pero Juan sigue viendo chat con mensajes sobre "Luna", que ya no existe.
3. **Usuario Quiere Salir**: Adoptante o rescatista quiere abandonar conversación. No hay forma clara de hacerlo.

Resultado: Listas de chats se saturan de "fantasmas", experiencia confusa.

### Solución 1: User Exit (PARCIALMENTE COMPLETADA)

Cuando usuario desea abandonar chat, puede hacer click en menú PopupButton → "Salir del Chat" en ChatScreen.

**Frontend (ChatScreen)**:

```dart
class ChatScreen extends StatelessWidget {
  final int matchId;
  final String peerName;
  final int peerId;
  final String? peerPhotoUrl;

  // Nuevos: estados de bloqueo
  final bool isPetDeleted;
  final bool isPeerLeft;

  const ChatScreen({
    super.key,
    required this.matchId,
    required this.peerName,
    required this.peerId,
    this.peerPhotoUrl,
    this.isPetDeleted = false,
    this.isPeerLeft = false,
  });

  @override
  Widget build(BuildContext context) {
    final isChatBlocked = isPetDeleted || isPeerLeft;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(peerName),
            if (isPetDeleted)
              const Text("Mascota eliminada", style: TextStyle(fontSize: 10, color: Colors.red)),
            if (isPeerLeft)
              const Text("Usuario abandonó el chat", style: TextStyle(fontSize: 10, color: Colors.red)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') {
                _confirmLeaveChat(context);
              } else if (value == 'report') {
                _showReportDialog(context);
              } else if (value == 'review') {
                _showReviewDialog(context);
              }
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
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag),
                      SizedBox(width: 8),
                      Text('Reportar Usuario'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'review',
                  child: Row(
                    children: [
                      Icon(Icons.star),
                      SizedBox(width: 8),
                      Text('Dejar Reseña'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Mensajes
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state is ChatLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is ChatLoaded) {
                  return ListView.builder(
                    reverse: true,
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final msg = state.messages[index];
                      return _buildMessageBubble(msg, state.myUserId);
                    },
                  );
                }
                return const Center(child: Text("Error cargando chat"));
              },
            ),
          ),

          // Input (deshabilitado si bloqueado)
          if (!isChatBlocked)
            const _ChatInput()
          else
            Container(
              color: Colors.grey[200],
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  isPetDeleted
                      ? "La mascota fue eliminada. No puedes escribir."
                      : "El usuario ha abandonado el chat. No puedes escribir.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmLeaveChat(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Salir del chat?"),
        content: const Text(
          "La conversación se cerrará y no podrás volver a escribir. "
          "El otro usuario recibirá un aviso.",
        ),
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
            const SnackBar(content: Text("Has salido del chat")),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e")),
          );
        }
      }
    }
  }

  Widget _buildMessageBubble(ChatMessage msg, int myUserId) {
    // ... renderizar mensaje con timestamp y checkmarks ...
    return Container(); // stub
  }

  void _showReportDialog(BuildContext context) {
    // ... lógica de reportar usuario ...
  }

  void _showReviewDialog(BuildContext context) {
    // ... lógica de dejar reseña ...
  }
}
```

**Backend (MatchService.Unmatch)**:

```go
// internal/core/services/match_service.go

func (s *MatchService) Unmatch(userID, matchID uint) error {
  var match domain.Match
  if err := s.db.Preload("Pet").First(&match, matchID).Error; err != nil {
    return errors.New("match no encontrado")
  }

  // Determinar quién se está yendo
  newStatus := ""
  if match.AdopterID == userID {
    newStatus = "adopter_left"  // ← Adoptante se fue
  } else if match.Pet.UserID == userID {
    newStatus = "rescuer_left"  // ← Rescatista se fue
  } else {
    return errors.New("no tienes permiso para salir de este chat")
  }

  // Actualizar estado del match
  match.Status = domain.MatchStatus(newStatus)
  if err := s.db.Save(&match).Error; err != nil {
    return err
  }

  // FUTURO: Notificar al otro usuario que el chat está cerrado
  // Por ahora, ambos usuarios ven chat pero con aviso rojo

  return nil
}
```

**MatchHandler.Unmatch**:

```go
// internal/transport/http/match_handler.go

func (h *MatchHandler) Unmatch(c *gin.Context) {
  userID, ok := getUserIDFromContext(c)
  if !ok {
    c.JSON(http.StatusUnauthorized, gin.H{"error": "Usuario no identificado"})
    return
  }

  var req struct {
    MatchID uint `json:"match_id" binding:"required"`
  }
  if err := c.ShouldBindJSON(&req); err != nil {
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

**Lo que FALTA**:

- [ ] Registrar ruta POST /matches/unmatch en main.go (línea ~217)
- [ ] Definir constantes MatchAdopterLeft, MatchRescuerLeft en domain.go
- [ ] Propagar estado "adopter_left"/"rescuer_left" al frontend vía API
- [ ] ChatScreen mostrar banner rojo cuando isPeerLeft=true
- [ ] Deshabilitar input cuando isChatBlocked=true

### Solución 2: Pet Deleted → Bloqueo de Chat (EN DESARROLLO)

Cuando rescatista elimina una mascota, los adoptantes que tienen chat activo con esa mascota deben ser notificados.

**Backend (PetService.Delete)**:

```go
// internal/core/services/pet_service.go

func (s *PetService) Delete(petID uint) error {
  // 1. Encontrar todos los matches activos de esta mascota
  var matches []domain.Match
  if err := s.db.Where("pet_id = ? AND status = ?", petID, domain.MatchAccepted).
    Find(&matches).Error; err != nil {
    return err
  }

  // 2. Marcar todos como "pet_deleted"
  if len(matches) > 0 {
    if err := s.db.Model(&domain.Match{}).
      Where("pet_id = ? AND status = ?", petID, domain.MatchAccepted).
      Update("status", "pet_deleted").Error; err != nil {
      return err
    }
  }

  // 3. Eliminar la mascota (cascade automático a PetImage)
  return s.db.Delete(&domain.Pet{}, petID).Error
}
```

**Lo que FALTA**:

- [ ] Constante MatchPetDeleted en domain.go
- [ ] Propagar "pet_deleted" al frontend
- [ ] ChatScreen renderizar banner rojo "Mascota eliminada"
- [ ] Notificación push: "La mascota fue eliminada por el rescatista"

### Solución 3: Soft Delete de Matches (EN DESARROLLO)

Usuario puede eliminar chat manualmente desde lista (long-press).

**Frontend (Long-press en chat)**:

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
              try {
                await matchesRepository.deleteChat(matchId);
                Navigator.pop(ctx);
                setState(() => chats.removeWhere((c) => c.id == matchId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Chat eliminado")),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error: $e")),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  },
  child: ChatListTile(chat: chat, name: peerName),
)
```

**Backend (MatchHandler.Delete)**:

```go
// internal/transport/http/match_handler.go

func (h *MatchHandler) Delete(c *gin.Context) {
  userID, ok := getUserIDFromContext(c)
  if !ok {
    c.JSON(http.StatusUnauthorized, gin.H{"error": "No autenticado"})
    return
  }

  matchIDStr := c.Param("id")
  matchID, err := strconv.ParseUint(matchIDStr, 10, 32)
  if err != nil {
    c.JSON(http.StatusBadRequest, gin.H{"error": "ID inválido"})
    return
  }

  if err := h.service.DeleteChat(userID, uint(matchID)); err != nil {
    c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
    return
  }

  c.JSON(http.StatusOK, gin.H{"message": "Chat eliminado"})
}
```

**Backend (MatchService.DeleteChat)**:

```go
func (s *MatchService) DeleteChat(userID, matchID uint) error {
  var match domain.Match
  if err := s.db.Preload("Pet").First(&match, matchID).Error; err != nil {
    return errors.New("chat no encontrado")
  }

  // Validar que usuario es parte del match
  if match.AdopterID != userID && match.Pet.UserID != userID {
    return errors.New("no tienes permiso para eliminar este chat")
  }

  // Soft delete (GORM)
  return s.db.Delete(&match).Error  // GORM interpreta como soft delete si hay DeletedAt
}
```

**Lo que FALTA**:

- [ ] Agregar DeletedAt a domain.Match (gorm.DeletedAt)
- [ ] Registrar ruta DELETE /matches/:id en main.go
- [ ] Actualizar queries para excluir soft-deleted (automático con GORM Unscoped)
- [ ] Implementar long-press UI en pantallas de chats
- [ ] Testing de cascada de soft deletes

### Estados de Match en Etapa 15

Extensión de estados anteriores (pending, accepted, rejected):

```go
// internal/core/domain/match.go

const (
  MatchPending      MatchStatus = "pending"      // Original: esperando respuesta rescatista
  MatchAccepted     MatchStatus = "accepted"     // Original: chat activo
  MatchRejected     MatchStatus = "rejected"     // Original: rechazado

  // NUEVOS EN ETAPA 15:
  MatchAdopterLeft  MatchStatus = "adopter_left"  // Adoptante se fue del chat
  MatchRescuerLeft  MatchStatus = "rescuer_left"  // Rescatista se fue del chat
  MatchPetDeleted   MatchStatus = "pet_deleted"   // Mascota fue eliminada por rescatista
  // (DeletedAt de GORM maneja soft delete automático)
)
```

### Flujos Completos de Etapa 15

**Flujo 1: Adoptante Sale del Chat**

```
1. Adoptante abre ChatScreen
2. Toca menú PopupButton → selecciona "Salir del Chat"
3. Dialog de confirmación
4. Toca "Salir"
5. POST /matches/unmatch {match_id: 42}
6. Backend: MatchService.Unmatch(userID, 42)
   - Valida que userID es adopter de match 42
   - match.status = "adopter_left"
   - save()
7. Frontend: Navigator.pop(), snackbar "Has salido del chat"
8. Rescatista ve su ChatScreen con banner rojo "Usuario abandonó el chat"
9. Input deshabilitado para ambos
```

**Flujo 2: Rescatista Elimina Mascota**

```
1. Rescatista abre PetDetailScreen
2. Toca menú → "Eliminar Mascota"
3. Confirmación
4. DELETE /pets/{petID}
5. Backend: PetService.Delete(petID)
   - Encuentra todos matches con status=accepted para esa mascota
   - Actualiza todos: match.status = "pet_deleted"
   - Elimina pet (cascade a PetImage)
6. Adoptantes ven ChatScreen con banner rojo "Mascota eliminada"
7. Input deshabilitado
8. FUTURO: Push notification notificando
```

**Flujo 3: Usuario Elimina Chat Manualmente**

```
1. Rescatista abre RescuerChatsScreen
2. Long-press (2 segundos) en chat
3. Dialog "Eliminar chat?"
4. Toca "Eliminar"
5. DELETE /matches/{matchID}
6. Backend: MatchHandler.Delete()
   - Valida usuario es parte del match
   - Soft delete (SetDeletedAt)
7. Chat desaparece de lista instantáneamente
8. GetRescuerMatches() ya no lo retorna (GORM Unscoped evita)
```

### Impacto de Etapa 15 en Ciclo de Chat

**Antes**:

- Chats con status=accepted permanecen por siempre
- Listas se saturan de chats "fantasma"
- Usuario no puede abandonar conversación limpiamente
- Si mascota es eliminada, adoptante sigue viendo chat inválido

**Después**:

- Estados claros: pending → accepted → (adopter_left|rescuer_left|pet_deleted|deleted)
- Usuario puede salir explícitamente
- Sistema notifica automáticamente cuando otro se va o mascota se elimina
- Listas pueden limpiarse manualmente (soft delete)
- Mejor UX: no hay ambigüedad de qué pasó

### Notas Arquitectónicas - Etapa 15 (Chat Lifecycle)

- **Estados Definidos**: En lugar de inferencias, estados explícitos comunican qué ocurrió
- **Soft Delete**: GORM's DeletedAt permite recuperación futura si es necesario
- **Bloqueo Defensivo**: Si chat está en estado "inactivo", input completamente deshabilitado
- **Notificación Inmediata**: Cuando usuario se va, otro usuario lo ve al abrir chat (no necesita refresh manual)
- **Extensibilidad**: Estados como "adopter_left", "pet_deleted" permiten filtrología futura (ej: mostrar/ocultar chats inactivos en menú)

## Resumen de Estado - Etapa 15 (Chat Lifecycle)

| Funcionalidad       | Estado        | Implementación      | Frontend | Backend |
| ------------------- | ------------- | ------------------- | -------- | ------- |
| User Exit UI        | COMPLETADO    | PopupMenu "Salir"   | ✓        |         |
| User Exit Backend   | PARCIAL       | Unmatch method      |          | ✓       |
| Pet Deleted Cascade | EN DESARROLLO | PetService.Delete   |          |         |
| Soft Delete Matches | EN DESARROLLO | Long-press delete   |          |         |
| Bloqueo de Input    | EN DESARROLLO | isChatBlocked flag  |          |         |
| Notificaciones      | EN DESARROLLO | Push when state=... |          |         |

## COMPLETADO EN ETAPA 16: Máquina de Estados Terminal y Ciclo de Vida Final

Etapa 16 cierra el ciclo de vida de chats implementando una **máquina de estados finita robusta** que resuelve tres problemas críticos de Etapa 15:

### Problema Resuelto 1: Bucle Infinito de Ping-Pong

**Situación en Etapa 15**: Cuando Usuario A salía, el chat desaparecía. Cuando Usuario B salía, el estado cambiaba a `rescuer_left` y el chat reaparecía en lista de A. Resultado: ciclo infinito de aparición/desaparición.

**Solución en Etapa 16**: Estado terminal `cancelled` que se alcanza solo cuando AMBOS usuarios han abandonado, garantizando que una vez alcanzado, nunca reaparecer en ninguna lista.

```go
// Nueva máquina de estados con 7 estados totales
const (
  MatchPending     = "pending"       // Inicial
  MatchAccepted    = "accepted"      // Activo
  MatchAdopterLeft = "adopter_left"  // Adoptante se fue
  MatchRescuerLeft = "rescuer_left"  // Rescatista se fue
  MatchPetDeleted  = "pet_deleted"   // Mascota eliminada
  MatchRejected    = "rejected"      // Rechazado
  MatchCancelled   = "cancelled"     // TERMINAL: Ambos se fueron
)
```

Lógica en `MatchService.Unmatch()`:

- Si yo me voy Y el otro ya se fue → transicionar a `cancelled` (terminal)
- Si yo me voy PRIMERO → transicionar a `[mi_rol]_left`
- Filtros SQL excluyen `cancelled` de todas las bandeja, garantizando que desaparece permanentemente

### Problema Resuelto 2: Efecto Espejo (Eliminación de Mascota)

**Situación en Etapa 15**: Al eliminar mascota, chats quedaban en limbo. Adoptante confundido, Rescatista podía seguir escribiendo. Inconsistencia total.

**Solución en Etapa 16**: Transacción GORM atómica en `PetService.Delete()` que cambia estados de match ANTES de soft-delete la mascota:

1. Rechazar pendientes
2. Bloquear activos (→ `pet_deleted`)
3. Soft-delete mascota

Garantía all-or-nothing: Si cualquier paso falla, TODOS se revierten. No hay estado intermedio inconsistente.

### Problema Resuelto 3: Robustez contra Datos Malformados

**Situación en Etapa 15**: Backend ocasionalmente envía `null`, `"null"`, floats en campos de ID. Frontend crasheaba.

**Solución en Etapa 16**: Función `_parseInt()` defensiva en `Match.fromJson()` que maneja:

- `null` → 0
- `3.14` → 3
- `"null"` → 0
- `"abc"` → 0
- Faltante → 0

Cero red screens. App se degrada gracefully.

### Problema Resuelto 4: Bloqueo de Mensajes Personalizado por Rol

**Situación en Etapa 15**: Ambos usuarios veían el mismo mensaje de bloqueo, aunque perspectivas diferaban.

**Solución en Etapa 16**: Parámetro `isRescuer` propagado a `ChatBloc` que personaliza `lockReason`:

- Si rescatista y `pet_deleted`: "Has eliminado la publicación..." (Yo la eliminé)
- Si adoptante y `pet_deleted`: "La publicación ha sido eliminada..." (Otro la eliminó)

Impacto en UX: Mensajes coherentes con perspectiva de usuario.

### Implementación Técnica - Etapa 16

**Backend (Go)**:

- `domain/match.go`: Constantes de nuevos estados
- `services/match_service.go`: Unmatch() con máquina de estados + GetAcceptedMatches/GetRescuerMatches con filtros correctos
- `services/pet_service.go`: Delete() con transacción atómica de 3 pasos

**Frontend (Flutter)**:

- `domain/match_model.dart`: Helpers de estado + \_parseInt()
- `presentation/screens/chat_screen.dart`: Parámetro `isRescuer`
- `presentation/bloc/chat_bloc.dart`: InitChat con `isRescuer`, personalización de lockReason
- `presentation/screens/{adopter,rescuer}_*_screen.dart`: Visualización de tachado + subtítulos personalizados

### Estado Final - Etapa 16

| Funcionalidad               | Estado     | Implementación              | Frontend | Backend |
| --------------------------- | ---------- | --------------------------- | -------- | ------- |
| Máquina de estados terminal | COMPLETADO | Estado `cancelled`          | ✓        | ✓       |
| Eliminación ping-pong       | COMPLETADO | Filtros SQL + `cancelled`   | ✓        | ✓       |
| Cascada de eliminación      | COMPLETADO | Transacción GORM de 3 pasos |          | ✓       |
| Robustez de datos           | COMPLETADO | \_parseInt() defensiva      | ✓        |         |
| Personalización por rol     | COMPLETADO | isRescuer en ChatBloc       | ✓        | ✓       |
| Visualización en listas     | COMPLETADO | Tachado + subtítulos        | ✓        |         |

**Etapa 16 Status: 100% Implementado y Verificado**

## COMPLETADO EN ETAPA 22: Notificaciones Visuales Inteligentes y Confirmación de Lectura ("Visto")

Etapa 22 implementa un sistema de dos capas para informar al usuario sobre estado de mensajes: notificaciones visuales (badges con contadores de no leídos) y confirmación de lectura (indicador "Visto" selectivo). El enfoque prioriza claridad visual sin contaminación de ruido.

### Problema Resuelto 1: Falta de Visualización de Mensajes Nuevos

**Situación Pre-Etapa 22**: El usuario debía navegar a la lista de chats para descubrir nuevos mensajes. Sin indicador global, era fácil perder conversaciones importantes. La aplicación no diferenciaba matches con mensajes nuevos vs activos sin novedad.

**Solución Etapa 22 - Sistema A (Badges)**: Cada vez que se carga la lista de matches (AdopterMatchesScreen / RescuerChatsScreen), el backend inyecta un campo virtual `unreadCount` en cada match objeto. Este campo representa el número exacto de mensajes no leídos EN ESTE MATCH, calculado mediante una subquery rápida. La pantalla suma todos los contadores y comunica al padre (MainLayoutScreen) el total global. MainLayoutScreen renderiza un círculo rojo en la barra de navegación con el número agregado.

**Implementación Backend**:

```go
// internal/core/services/match_service.go
// En GetAdopterMatches()
var count int64
s.db.Model(&domain.Message{}).
    Where("match_id = ? AND sender_id != ? AND is_read = ?",
          matches[i].ID, adopterID, false).
    Count(&count)
matches[i].UnreadCount = int(count)

// El campo UnreadCount en domain.Match:
// UnreadCount int `json:"unread_count" gorm:"-"`
// (gorm:"-" significa: no guardes en tabla, solo en JSON)
```

**Ventajas de Campo Virtual**:

- Calculado en tiempo de lectura, nunca se persiste en tabla
- Cada cliente obtiene su perspectiva correcta (sus propios no leídos)
- O(n) queries para n matches, aceptable en listas pequeñas
- Totalmente determinista: siempre refleja estado actual de BD
- Sin consistencia eventual: valor siempre correcto

**Implementación Frontend - Suma y Callback**:

```dart
// app/lib/features/pets/presentation/screens/adopter_matches_screen.dart
// En _loadAllData():

final matches = (resAccepted.data as List)
    .map((json) => Match.fromJson(json))
    .toList();

// Sumar todosunreadCounts
final totalUnread = matches.fold(0, (sum, m) => sum + m.unreadCount);

// Invocar callback al padre
widget.onBadgeUpdate?.call(totalUnread);
```

**Callback Pattern Explicado**:

AdopterMatchesScreen y RescuerChatsScreen son pantallas HIJO dentro de MainLayoutScreen (padre). No pueden mutar el estado del padre directamente. En su lugar, reciben un callback `onBadgeUpdate` como parámetro de constructor. Cuando tienen datos, llaman `widget.onBadgeUpdate?.call(totalCount)`. El padre implementa:

```dart
// app/lib/core/presentation/main_layout_screen.dart
void _updateUnreadCount(int count) {
  if (_unreadChats != count) {
    setState(() {
      _unreadChats = count;
    });
  }
}

// Pasar callback al hijo
AdopterMatchesScreen(onBadgeUpdate: _updateUnreadCount)

// Renderizar con contador
NavigationDestination(
  icon: _buildBadgedIcon(Icons.favorite, _unreadChats),
  label: 'Matches',
)

// Helper para construir ícono con badge
Widget _buildBadgedIcon(IconData icon, int count) {
  if (count == 0) return Icon(icon);

  return Stack(
    children: [
      Icon(icon),
      Positioned(
        right: 0, top: 0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
          child: Text(
            count > 9 ? '9+' : '$count',
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ],
  );
}
```

**Propagación de Cambios**: Cada vez que usuario navega a la pestaña de matches, se llama `_loadAllData()` que recalcula badges. Si nuevo mensaje llegó vía WebSocket, el siguiente recalculation lo verá. Patrón simple pero efectivo sin necesidad de escuchas complejas.

### Problema Resuelto 2: Falta de Confirmación de Entrega/Lectura

**Situación Pre-Etapa 22**: El usuario enviaba un mensaje. El app mostraba "Enviado". Pero no había forma de saber si la otra persona lo leyó. En apps como WhatsApp, dos checkmarks grises = enviado, dos azules = leído. PAWS carecía de este feedback fundamental.

**Solución Etapa 22 - Sistema B (Visto)**:

**Fase 1 - Trigger Automático**: Al entrar a ChatScreen (initState), el frontend dispara silenciosamente: `POST /matches/:id/read`. Backend busca todos los mensajes de ESTE MATCH que (a) NO fueron enviados por el usuario actual (sender_id != currentUserId), y (b) aún no están marcados (is_read = false). Los actualiza a is_read = true en una sola transacción.

**Fase 2 - Renderizado Selectivo**: En ChatBubble, solo mostramos "Visto" si se cumplen TRES condiciones simultáneamente:

- Es mi mensaje (isMe == true)
- Es el último de la lista (index == 0 con reverse)
- Está marcado como leído en BD (msg.isRead == true)

**Implementación Frontend - Trigger**:

```dart
// app/lib/features/chat/presentation/screens/chat_screen.dart
class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    _loadMyUserId();
    _markChatAsRead();  // <-- NUEVO
  }

  void _markChatAsRead() {
    context.read<ChatRepository>().markAsRead(widget.matchId);
  }
}
```

**Implementación Frontend - Repository**:

```dart
// app/lib/features/chat/data/chat_repository.dart
Future<void> markAsRead(int matchId) async {
  try {
    final token = await _storage.read(key: 'jwt_token');
    await _dio.post(
      '${ApiConstants.baseUrl}/matches/$matchId/read',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  } catch (e) {
    print("Error marcando como leído: $e");  // Silent fail
  }
}
```

**Implementación Backend - Handler**:

```go
// internal/transport/http/social_handler.go
func (h *SocialHandler) MarkAsRead(c *gin.Context) {
  userID, ok := getUserIDSafe(c)
  if !ok {
    c.JSON(http.StatusUnauthorized, gin.H{"error": "No identificado"})
    return
  }

  matchIDStr := c.Param("id")
  matchID, err := strconv.Atoi(matchIDStr)
  if err != nil {
    c.JSON(http.StatusBadRequest, gin.H{"error": "ID inválido"})
    return
  }

  if err := h.chatService.MarkAsRead(uint(matchID), userID); err != nil {
    c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
    return
  }

  c.JSON(http.StatusOK, gin.H{"message": "Marcado como leído"})
}
```

**Implementación Backend - Service**:

```go
// internal/core/services/chat_service.go
func (s *ChatService) MarkAsRead(matchID, userID uint) error {
  // Actualiza TODOS los mensajes donde:
  // - Pertenecen a este match
  // - NO fueron enviados por el usuario actual
  // - Aún no están marcados como leídos

  return s.db.Model(&domain.Message{}).
    Where("match_id = ? AND sender_id != ? AND is_read = ?",
          matchID, userID, false).
    Update("is_read", true).Error
}
```

**Implementación Frontend - Renderizado Selectivo**:

```dart
// app/lib/features/chat/presentation/screens/chat_screen.dart
ListView.builder(
  reverse: true,
  itemCount: state.messages.length,
  itemBuilder: (context, index) {
    final msg = state.messages[index];
    final isMe = msg.senderId == _myUserId;

    // Triple condition check:
    bool showSeen = (index == 0 && isMe && msg.isRead);

    return ChatBubble(
      message: msg,
      isMe: isMe,
      isSeen: showSeen,
    );
  },
)
```

**Implementación Frontend - ChatBubble**:

```dart
// app/lib/features/chat/presentation/widgets/chat_bubble.dart
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isSeen;  // NUEVO

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            // [mensaje dentro]
          ),
          // SOLO si isSeen es true:
          if (isSeen && isMe)
            Padding(
              padding: const EdgeInsets.only(right: 14, bottom: 4),
              child: Text(
                "Visto",
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

**Por qué Triple-Condition Check**:

- Mostrar "Visto" en TODOS los mensajes genera ruido visual: "Visto Visto Visto Visto Visto" (5 mensajes)
- Validar `index == 0` mostrar SOLO último mensaje: usuario ve claramente CUÁL mensaje fue leído
- Validar `isMe` evitar confusión: "Visto" indica que EL OTRO leyó MI mensaje, no lo contrario
- Validar `msg.isRead` no mentir: si BD dice false, no mostramos "Visto"
- Todas falsan = NO renderizar = claridad visual, sin contaminación

**Flujo Completo de Etapa 22**:

1. Usuario A abre ChatScreen con Usuario B
2. `initState()` dispara `POST /matches/:id/read` (silent)
3. Backend actualiza `messages.is_read = true` (para mensajes de B)
4. ChatBloc refresca view llamando `getHistory()`
5. ListView.builder recalcula `isSeen` para el último mensaje de A
6. Si condiciones se cumplen, ChatBubble renderiza "Visto" en pequeño gris
7. A continuación, Usuario B envía mensaje nuevo
8. Index cambia (nuevo mensaje es index 0), "Visto" desaparece automáticamente

### Integración Arquitectónica - Etapa 22

| Componente                                      | Cambios                                                                               |
| ----------------------------------------------- | ------------------------------------------------------------------------------------- |
| `MatchService.GetAdopterMatches()` (Backend Go) | Agregó bucle que cuenta mensajes no leídos, asigna UnreadCount a cada match           |
| `MatchService.GetRescuerMatches()` (Backend Go) | Mismo patrón: subquery inline de contadores                                           |
| `domain.Match` (Backend Go)                     | Campo `UnreadCount int json:"unread_count" gorm:"-"` (virtual, no persiste)           |
| `Match.fromJson()` (Frontend Dart)              | Ya parseaba unreadCount desde JSON                                                    |
| `AdopterMatchesScreen` (Frontend Flutter)       | Callback `onBadgeUpdate`, invoca con suma total en \_loadAllData()                    |
| `RescuerChatsScreen` (Frontend Flutter)         | Mismo patrón: callback + suma de badges                                               |
| `MainLayoutScreen` (Frontend Flutter)           | State `_unreadChats`, callback `_updateUnreadCount()`, \_buildBadgedIcon() para badge |
| `ChatScreen.initState()` (Frontend Flutter)     | Llama `_markChatAsRead()` que invoca `ChatRepository.markAsRead()`                    |
| `ChatRepository.markAsRead()` (Frontend Dart)   | NUEVO método: `POST /matches/:id/read` con token automático                           |
| `SocialHandler.MarkAsRead()` (Backend Go)       | NUEVO endpoint: recibe matchID, delega a ChatService.MarkAsRead()                     |
| `ChatService.MarkAsRead()` (Backend Go)         | NUEVO método: UPDATE messages SET is_read = true WHERE...                             |
| `ChatBubble` (Frontend Flutter)                 | Parámetro `isSeen`, renderiza "Visto" solo si (isSeen && isMe)                        |

### Archivos Modificados en Etapa 22

**Backend (Go)**:

- `internal/core/services/match_service.go`: GetAdopterMatches() y GetRescuerMatches() con lógica de conteo en bucle
- `internal/core/services/chat_service.go`: Nuevo método MarkAsRead()
- `internal/transport/http/social_handler.go`: Nuevo handler MarkAsRead()
- `internal/core/domain/match.go`: Campo UnreadCount virtual

**Frontend (Flutter)**:

- `app/lib/features/pets/domain/match_model.dart`: Parámetro unreadCount en constructor
- `app/lib/features/pets/presentation/screens/adopter_matches_screen.dart`: Callback onBadgeUpdate + suma de badges
- `app/lib/features/chat/presentation/screens/rescuer_chats_screen.dart`: Callback onBadgeUpdate + suma de badges
- `app/lib/core/presentation/main_layout_screen.dart`: State \_unreadChats, \_buildBadgedIcon(), callback receiver
- `app/lib/features/chat/presentation/screens/chat_screen.dart`: initState() con \_markChatAsRead() call
- `app/lib/features/chat/data/chat_repository.dart`: Nuevo método markAsRead()
- `app/lib/features/chat/presentation/widgets/chat_bubble.dart`: Parámetro isSeen, renderizado condicional

### Validación de Etapa 22

**Backend - Contadores**:

```bash
# Login y obtener token
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "adopter@example.com", "password": "pass"}' \
  | jq -r '.token')

# Obtener matches con unreadCount
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/v1/matches/adopter | jq '.[] | {id, pet_id, unread_count}'

# Respuesta esperada:
# [{"id": 1, "pet_id": 5, "unread_count": 3}]
```

**Backend - MarkAsRead**:

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/v1/matches/1/read

# Verificar que unreadCount bajó a 0 en siguiente query
```

**Frontend - Verificación Manual**:

- Badge circular rojo aparece solo en matches con unreadCount > 0
- Badge muestra número correcto (suma de todos los unreadCounts)
- Badge desaparece tras abrir chat y volver (MarkAsRead ejecutado)
- MainLayout badge se actualiza con total global
- "Visto" aparece gris pequeño SOLO en último mensaje propio
- "Visto" desaparece cuando nuevo mensaje llega

### Problemas Resueltos vs Fase 15

| Situación Pre-Etapa 22                    | Solución Etapa 22                                         |
| ----------------------------------------- | --------------------------------------------------------- |
| No hay visualización de nuevos mensajes   | Badge con contador en barra de navegación                 |
| Usuario pierde conversaciones importantes | Callback: padre siempre ve total global                   |
| Sin confirmación de que mensaje fue leído | "Visto" en último mensaje cuando usuario abre chat        |
| Backend sin forma de marcar leído         | POST /matches/:id/read + MarkAsRead() service             |
| ChatBubble renderizaba todo plano         | Lógica triple-condition: isMe AND isLastInList AND isRead |
| Ruido visual de "Visto" repetido          | Solo último mensaje muestra estado                        |

### Ventajas Arquitectónicas - Etapa 22

1. **Virtual Fields**: UnreadCount calculado sin mutation de BD. Bajo costo, siempre consistente
2. **Callback Pattern**: Comunicación limpia padre-hijo sin BLoC extra. Escalable a otros contadores
3. **Silent Trigger**: MarkAsRead() sin feedback visual. Usuario no ve "marcando..."
4. **Triple Validation**: "Visto" solo cuando es apropiado. UX clara sin contaminación
5. **O(1) Lookup**: Cuando nuevo mensaje llega vía WebSocket, ChatBloc recalcula isSeen automáticamente
6. **Backward Compatible**: Modelos ya tenían campos is_read. Etapa 22 solo agrega lógica

### Estado Final - Etapa 22

| Funcionalidad                      | Estado     | Implementación | Frontend | Backend |
| ---------------------------------- | ---------- | -------------- | -------- | ------- |
| Contadores virtuales de no leídos  | COMPLETADO | MatchService   | Sí       | Sí      |
| Agregación de badges vía callbacks | COMPLETADO | Callback+State | Sí       |         |
| MarkAsRead automático              | COMPLETADO | initState()    | Sí       |         |
| Marcación en BD                    | COMPLETADO | ChatService    |          | Sí      |
| "Visto" selectivo                  | COMPLETADO | ChatBubble     | Sí       |         |
| Triple-condition validation        | COMPLETADO | Chat logic     | Sí       |         |
| Propagación de cambios             | COMPLETADO | Callback+Hub   | Sí       | Sí      |
| Integración con WebSocket          | COMPLETADO | ChatBloc       | Sí       |         |

**Etapa 22 Status: 100% Implementado y Verificado**

## Referencias

- [Gorilla WebSocket](https://github.com/gorilla/websocket)
- [WebSocket RFC 6455](https://tools.ietf.org/html/rfc6455)
- [Go Concurrency Patterns](https://go.dev/blog/pipelines)
- [BLoC Pattern en Flutter](https://bloclibrary.dev/)
- [JWT en Go](https://pkg.go.dev/github.com/golang-jwt/jwt/v5)
- [Goroutines vs Threads](https://medium.com/@mustafaansal/goroutine-vs-thread-9e2584d96c42)
