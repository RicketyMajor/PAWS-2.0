# Fase 11: Notificaciones Asincrónicas, Email & Mensajería (EN DESARROLLO - INESTABLE)

## ADVERTENCIA CRÍTICA

Esta es una **fase experimental e incompleta**. Se han implementado parcialmente características de:

- Integración con RabbitMQ para cola de mensajes
- Cliente SendGrid para envío de emails
- Worker asincrónico para procesar eventos de email
- Refactorización de OTPService para usar RabbitMQ
- Cambios en el frontend para manejo de notificaciones

**ESTADO**: Desarrollo activo. Altamente propensa a errores, fallos de integración, y cambios disruptivos. NO se recomienda implementar en producción ni integrar en la rama principal.

---

## Introducción

Fase 11 representa un cambio fundamental en la arquitectura de PAWS. Hasta Fase 10, todas las operaciones eran síncronas: un usuario ejecuta acción → servidor responde inmediatamente. Pero esta arquitectura no escala bien para operaciones costosas como envío de emails.

### El Problema (Why Async?)

En Fase 8, cuando un usuario registra, debe:

1. Generar OTP
2. Enviar email con OTP
3. Responder al cliente

Si SendGrid tarda 2 segundos, el cliente espera 2 segundos. Con 1000 usuarios simultáneos = 2000 segundos de latencia agregada. Inaceptable.

### La Solución (Event-Driven)

Fase 11 introduce una arquitectura **event-driven**:

1. **Evento generado**: Usuario solicita OTP
2. **Publicado en cola**: OTPService publica evento a RabbitMQ
3. **Respuesta inmediata**: Servidor responde al cliente en 100ms
4. **Procesado en background**: Worker de Email consume evento y envía email sin bloquear al usuario

**Beneficios**:

- Baja latencia para cliente (respuesta inmediata)
- Escalabilidad (múltiples workers pueden procesar eventos)
- Resiliencia (si SendGrid cae, evento queda en cola y se reintenta)
- Desacoplamiento (OTPService no necesita saber sobre SendGrid)

---

## Arquitectura - Componentes Nuevos (Fase 11)

### 1. RabbitMQ (Message Broker)

**Archivo**: `internal/infrastructure/messaging/rabbitmq.go`
**Líneas**: 70 aprox.
**Propósito**: Broker central de mensajes. Conecta productores (OTPService) con consumidores (EmailWorker).

**Características**:

```go
type RabbitMQClient struct {
    conn *amqp.Connection
    ch   *amqp.Channel
}

func ConnectRabbitMQ(url string) (*RabbitMQClient, error) {
    // Lógica de reintento (Wait for infrastructure)
    // Declara cola "email_notifications" (durable: true)
    // Retorna *RabbitMQClient
}

func (c *RabbitMQClient) Publish(queueName string, body []byte) error {
    // Publica mensaje a cola
    // ContentType: "application/json"
    // DeliveryMode: amqp.Persistent (guardar en disco)
}

func (c *RabbitMQClient) GetChannel() *amqp.Channel {
    // Exporta canal para consumidores
}

func (c *RabbitMQClient) Close() {
    // Cierra conexión
}
```

**Flujo**:

1. `ConnectRabbitMQ("amqp://guest:guest@rabbitmq-service:5672/")` → Conecta a broker
2. Si falla, reintenta 5 veces (wait for infrastructure pattern)
3. Declara cola "email_notifications" como durable (sobrevive reinicios)
4. Retorna cliente listo

**Error Handling**:

- Si RabbitMQ no está disponible, sistema continúa (log en consola)
- OTPService fallback: si `mqClient == nil`, loguea en consola en lugar de publicar

**PROBLEMAS CONOCIDOS** (Fase 11 EN DESARROLLO):

- Falta agregar RabbitMQ a docker-compose.yml
- Falta configurar variables de entorno (RABBITMQ_URL)
- Falta lógica de reintento para mensajes fallidos (dead letter queue)
- Falta autenticación con usuario/password en docker-compose

### 2. SendGrid Client (Email Provider)

**Archivo**: `internal/infrastructure/email/sendgrid_client.go`
**Líneas**: 50 aprox.
**Propósito**: Abstracción para envío de emails reales o simulados.

**Características**:

```go
type EmailClient struct {
    apiKey string
}

func NewEmailClient() *EmailClient {
    // Lee SENDGRID_API_KEY de variables de entorno
    // Si no existe, modo mock
}

func (c *EmailClient) Send(to, subject, body string) error {
    if c.apiKey == "" {
        // MOCK: Loguea en consola [MOCK EMAIL]
        return nil
    }

    // REAL: Usa SendGrid API
    // From: "PAWS Security" <no-reply@paws.cl>
    // To: parámetro `to`
    // Subject: parámetro `subject`
    // Body: PlainText y HTML (iguales por ahora)

    // Verifica statusCode >= 400 → error
}
```

**Flujo**:

1. Desarrollo (sin API Key): Log en consola
2. Producción (con API Key): Envío real via SendGrid
3. Error handling: Retorna error si statusCode >= 400

**PROBLEMAS CONOCIDOS** (Fase 11 EN DESARROLLO):

- Falta agregar SENDGRID_API_KEY a .env y docker-compose
- Falta validación de formato de email
- Falta implementación de HTML templates (actualmente plaintext)
- Falta retry logic si SendGrid falla
- Falta logging estructurado (actualmente log.Printf)

### 3. Email Worker (Consumer)

**Archivo**: `internal/core/workers/email_worker.go`
**Líneas**: 65 aprox.
**Propósito**: Consume eventos de cola RabbitMQ y envía emails asincronamente.

**Características**:

```go
type EmailEvent struct {
    To      string `json:"to"`
    Subject string `json:"subject"`
    Body    string `json:"body"`
}

func StartEmailConsumer(mq *messaging.RabbitMQClient,
                        emailClient *email.EmailClient) {
    // 1. Abre canal RabbitMQ
    // 2. Consume de "email_notifications"
    // 3. Bucle infinito:
    //    - Decodifica JSON
    //    - Llama emailClient.Send()
    //    - Si éxito: d.Ack(false) [confirma a broker]
    //    - Si error: Log y continúa (NO reintenta automático)
}
```

**Flujo Detallado**:

```
Inicio del servidor (main.go):
  1. Conecta RabbitMQ
  2. Crea EmailClient (SendGrid)
  3. Llama StartEmailConsumer(mq, emailClient)
     ↓
  4. StartEmailConsumer inicia goroutine (go func() { ... })
     ↓
  5. Consume forever loop:
     - Espera mensaje en "email_notifications"
     - Decodifica EmailEvent JSON
     - emailClient.Send(event.To, event.Subject, event.Body)
     - d.Ack(false) confirma a RabbitMQ
```

**Error Handling**:

- JSON decode error: Ack anyway (descarta mensaje malformado)
- Email send error: Log y continúa (SIN reintento automático)

**PROBLEMAS CONOCIDOS** (Fase 11 EN DESARROLLO):

- Falta implementar reintento exponencial
- Falta Dead Letter Queue para mensajes fallidos
- Falta límite de rate (si SendGrid rechaza por rate limit)
- Falta circuit breaker si SendGrid está caído
- Falta métrica de eventos procesados/fallidos
- Worker no se detiene gracefully en shutdown

### 4. OTPService Refactorizado (Async)

**Archivo**: `internal/core/services/otp_service.go`
**Líneas**: 96 aprox.
**Cambios desde Fase 8**:

**ANTES (Fase 8 - Sincrónico)**:

```go
func (s *OTPService) GenerateOTP(email string) (string, error) {
    code := fmt.Sprintf("%06d", rand.Intn(1000000))
    s.redisClient.Set(ctx, "otp:" + email, code, 5 * time.Minute)

    // Envío bloqueante (2 segundos!)
    sendEmailToProvider(email, "Tu código: " + code)

    return code, nil
}
```

**AHORA (Fase 11 - Asincrónico)**:

```go
type OTPService struct {
    redisClient *redis.Client
    mqClient    *messaging.RabbitMQClient  // <--- NUEVO
}

func NewOTPService(mq *messaging.RabbitMQClient) *OTPService {
    return &OTPService{
        redisClient: redis.NewClient(...),
        mqClient:    mq,
    }
}

func (s *OTPService) GenerateOTP(email string) (string, error) {
    code := fmt.Sprintf("%06d", rand.Intn(1000000))
    s.redisClient.Set(ctx, "otp:" + email, code, 5 * time.Minute)

    // Publicar evento (< 10ms!)
    event := EmailEvent{
        To:      email,
        Subject: "Tu código de verificación PAWS",
        Body:    fmt.Sprintf("Tu código es: %s. Válido por 5 minutos.", code),
    }

    eventBytes, _ := json.Marshal(event)

    if s.mqClient != nil {
        s.mqClient.Publish("email_notifications", eventBytes)
    } else {
        // Fallback: Log en consola
        log.Printf("[DEV] Para: %s | Código: %s", email, code)
    }

    return code, nil
}
```

**Diferencia Clave**:

- **Fase 8**: `sendEmail()` bloqueante en mismo thread → ~2000ms
- **Fase 11**: `mqClient.Publish()` no bloqueante → ~10ms

**PROBLEMAS CONOCIDOS** (Fase 11 EN DESARROLLO):

- Falta validación si email es válido
- Falta de duplicación de eventos (usuario solicita OTP 2 veces = 2 emails)
- Falta timeout en conexión a RabbitMQ
- Fallback a consola es suficiente solo para desarrollo

---

## Cambios en main.go (Integración Fase 11)

**Archivo**: `cmd/api/main.go`
**Cambios principales**:

### Antes (Fase 10):

```go
func main() {
    database.Connect()
    database.DB.AutoMigrate(&domain.User{}, &domain.Pet{}, ...)

    hub := httpTransport.NewHub()
    go hub.Run()

    // ... rest of services
}
```

### Ahora (Fase 11):

```go
func main() {
    database.Connect()
    database.DB.AutoMigrate(&domain.User{}, &domain.Pet{}, ...)

    // ========== NUEVO: RabbitMQ =========
    mqClient, err := messaging.ConnectRabbitMQ("amqp://guest:guest@rabbitmq-service:5672/")
    if err != nil {
        log.Println("RabbitMQ no disponible. El sistema funcionará, pero sin eventos asíncronos.")
    } else {
        defer mqClient.Close()
        log.Println("Conectado a RabbitMQ")
    }

    // ========== NUEVO: SendGrid =========
    emailClient := email.NewEmailClient()

    // ========== NUEVO: Email Worker =========
    if mqClient != nil {
        workers.StartEmailConsumer(mqClient, emailClient)
    }

    hub := httpTransport.NewHub()
    go hub.Run()

    // ========== ACTUALIZADO: OTPService recibe mqClient =========
    otpService := services.NewOTPService(mqClient)  // <- Inyectamos RabbitMQ

    // ... rest of services using otpService
}
```

**Order of Initialization** (CRÍTICO):

1. Database connect
2. RabbitMQ connect (can fail gracefully)
3. SendGrid client creation
4. Email worker startup (solo si RabbitMQ connected)
5. Services initialization (with mqClient dependency)
6. Hub & WebSocket
7. HTTP server startup

**PROBLEMAS CONOCIDOS** (Fase 11 EN DESARROLLO):

- Falta validación de SENDGRID_API_KEY disponibilidad
- Falta graceful shutdown (cerrar RabbitMQ, workers, etc.)
- Falta health check endpoint para monitorear estado de RabbitMQ
- Email worker no se detiene al shutdown del servidor

---

## Cambios en Infraestructura (Docker)

### INCOMPLETO: docker-compose.yml

**Estado Actual**: Falta RabbitMQ service.

**Debería agregar** (NO HECHO AÚN):

```yaml
  # 5. MESSAGE BROKER (RABBITMQ) - NUEVO EN FASE 11
  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    container_name: paws-rabbitmq
    restart: always
    ports:
      - "5672:5672"   # AMQP protocol
      - "15672:15672" # Management console
    environment:
      RABBITMQ_DEFAULT_USER: guest
      RABBITMQ_DEFAULT_PASS: guest
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq

volumes:
  postgres_data:
  minio_data:
  rabbitmq_data:  # <--- NUEVA
```

**Y actualizar backend service**:

```yaml
backend:
  # ... existing config ...
  depends_on:
    - db
    - redis
    - rabbitmq # <--- NUEVA DEPENDENCIA
  environment:
    # ... existing env vars ...
    RABBITMQ_URL: "amqp://guest:guest@rabbitmq-service:5672/"
    SENDGRID_API_KEY: "${SENDGRID_API_KEY:-}" # Empty en dev
```

**PROBLEMAS CONOCIDOS**:

- RabbitMQ no está en docker-compose.yml
- Backend intenta conectar a "rabbitmq-service:5672/" pero no existe
- SENDGRID_API_KEY no está configurado
- Sin RabbitMQ, OTPService falla silenciosamente y loguea en consola

---

## Cambios en Frontend (Fase 11)

### ChatRepository - Integración con Persistencia

**Archivo**: `app/lib/features/chat/data/chat_repository.dart`
**Cambios desde Fase 10**:

**NUEVA FUNCIONALIDAD**:

```dart
class ChatRepository {
    final Dio _dio = Dio();
    final FlutterSecureStorage _storage = const FlutterSecureStorage();
    WebSocketChannel? _channel;

    // NUEVO: Decodificar JWT para obtener user ID
    Future<int> _getMyUserId() async {
        final token = await _storage.read(key: 'jwt_token');
        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
        return int.tryParse(decodedToken['sub'] ??
                            decodedToken['user_id'].toString()) ?? 0;
    }

    // NUEVA: Cargar historial persistente desde BD
    Future<List<ChatMessage>> getHistory(int matchId) async {
        final token = await _storage.read(key: 'jwt_token');
        final myId = await _getMyUserId();

        final response = await _dio.get(
            '${ApiConstants.baseUrl}/matches/$matchId/messages',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
        );

        List<dynamic> data = response.data;
        return data.map((json) => ChatMessage.fromJson(json, myId)).toList();
    }

    // ACTUALIZADO: WebSocket ahora persiste via backend
    Future<Stream<dynamic>> connectToChat() async {
        final token = await _storage.read(key: 'jwt_token');
        final uri = Uri.parse(ApiConstants.wsUrl);

        _channel = IOWebSocketChannel.connect(
            uri,
            headers: {'Authorization': 'Bearer $token'},
        );

        return _channel!.stream;
    }

    // ACTUALIZADO: sendMessage enviado a ws_handler que persiste
    void sendMessage(int matchId, String content) {
        final messageJson = jsonEncode({
            'match_id': matchId,
            'content': content
        });
        _channel!.sink.add(messageJson);
    }
}
```

**Cambio Conceptual**:

- Fase 10: Historial en BD, pero cliente no lo cargaba
- Fase 11: Cliente carga historial al abrir chat + conecta WS
- Resultado: El usuario ve historial previo antes de mensajes nuevos

### ChatBloc - Optimistic Updates & Error Handling

**Archivo**: `app/lib/features/chat/presentation/bloc/chat_bloc.dart`
**Cambios desde Fase 10**:

**NUEVOS EVENTOS**:

```dart
class InitChat extends ChatEvent {
    final int matchId;
    InitChat(this.matchId);  // <--- Inicializar con matchId
}

class SendMessageEvent extends ChatEvent {
    final String content;
    SendMessageEvent(this.content);
}

class _ReceiveMessageEvent extends ChatEvent {
    final ChatMessage message;
    _ReceiveMessageEvent(this.message);
}
```

**NUEVOS ESTADOS**:

```dart
class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
    final List<ChatMessage> messages;
    final int matchId;

    ChatLoaded({required this.messages, required this.matchId});
}

class ChatError extends ChatState {
    final String error;
    ChatError(this.error);
}
```

**FLUJO (Optimistic Updates)**:

```dart
on<InitChat>((event, emit) async {
    emit(ChatLoading());

    try {
        // 1. Cargar historial BD (HTTP)
        final history = await repository.getHistory(event.matchId);
        emit(ChatLoaded(messages: history, matchId: event.matchId));

        // 2. Conectar WebSocket para mensajes nuevos
        final stream = await repository.connectToChat();

        // 3. Escuchar stream en background
        _wsSubscription = stream.listen((data) {
            final newMsg = ChatMessage(...)  // Parse del backend
            add(_ReceiveMessageEvent(newMsg));
        }, onError: (error) => print("WS Error"));
    } catch (e) {
        emit(ChatError(e.toString()));
    }
});

on<SendMessageEvent>((event, emit) async {
    if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;

        // 1. Enviar por WS (no bloqueante)
        repository.sendMessage(_currentMatchId, event.content);

        // 2. Optimistic Update: agregar a lista local inmediatamente
        final myMsg = ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch,
            matchId: _currentMatchId,
            senderId: 999,  // Temporal
            content: event.content,
            isMe: true,
        );

        // 3. Emitir estado actualizado (usuario ve su mensaje al instante)
        emit(ChatLoaded(
            messages: [...currentState.messages, myMsg],
            matchId: _currentMatchId,
        ));
    }
});
```

**UX Improvement** (Fase 11 vs Fase 10):

- Fase 10: Usuario envía mensaje → espera respuesta backend → lo ve en pantalla (100-200ms delay)
- Fase 11: Usuario envía mensaje → aparece inmediatamente en pantalla (0ms) → backend lo persiste en background

**PROBLEMAS CONOCIDOS** (Fase 11 EN DESARROLLO):

- Falta manejo de conflictos si mensaje no se persist en BD
- Falta deduplicación de mensajes (recibido por WS + cargado por GET)
- Falta marcado de "enviando..." mientras se guarda en BD
- Falta retry si mensaje falla en persistencia
- Falta indicador de "escribiendo..." del otro usuario
- Falta marca de "leído" en mensajes

---

## Cambios en Modelos (Frontend)

### ChatMessage Model - Ampliación

**Archivo**: `app/lib/features/chat/domain/message_model.dart`

**Cambios Esperados** (IMPLEMENTACIÓN INCOMPLETA):

```dart
class ChatMessage extends Equatable {
    final int id;
    final int matchId;
    final int senderId;
    final String content;
    final bool isRead;        // <--- NUEVO (del BD)
    final DateTime createdAt; // <--- NUEVO (del BD)
    final bool isMe;          // <--- NUEVO (UI state)

    ChatMessage({
        required this.id,
        required this.matchId,
        required this.senderId,
        required this.content,
        required this.isRead,
        required this.createdAt,
        required this.isMe,
    });

    // NUEVO: Factory para parsear desde JSON (BD)
    factory ChatMessage.fromJson(Map<String, dynamic> json, int myUserId) {
        return ChatMessage(
            id: json['id'],
            matchId: json['match_id'],
            senderId: json['sender_id'],
            content: json['content'],
            isRead: json['is_read'] ?? false,
            createdAt: DateTime.parse(json['created_at']),
            isMe: json['sender_id'] == myUserId,
        );
    }

    @override
    List<Object> get props => [id, matchId, senderId, content, isRead, createdAt];
}
```

**PROBLEMAS CONOCIDOS**:

- Factory `fromJson` puede no estar implementado
- Falta serialización `toJson()` si se necesita
- Falta validación de timestamp parsing
- Falta manejo de timezone (UTC vs local)

---

## Problemas & Errores Conocidos (Fase 11)

### Backend

1. **RabbitMQ No Está en Docker**

   - Error: "no se pudo conectar a RabbitMQ"
   - Solución: Agregar servicio RabbitMQ a docker-compose.yml
   - Estado: NO HECHO

2. **OTPService Falla Silenciosamente**

   - Si RabbitMQ no está disponible, OTPService loguea en consola
   - Usuario cree que recibió email pero no llega
   - Estado: CRÍTICO

3. **Fallback a Consola Es Inaceptable en Producción**

   - Ambiente dev: Aceptable loguear OTP en consola
   - Ambiente prod: Debe fallar explícitamente o tener fallback a SendGrid sincrónico
   - Estado: NO IMPLEMENTADO

4. **Email Worker No Tiene Reintento**

   - Si SendGrid rechaza un email, se descarta
   - Usuario nunca recibe email pero no hay error
   - Estado: CRÍTICO

5. **No Hay Circuit Breaker**

   - Si SendGrid está caído, worker reintentar infinitamente
   - Consume recursos pero no logra enviar
   - Estado: NO IMPLEMENTADO

6. **Shutdown No Es Graceful**
   - Si servidor se reinicia, email worker se mata
   - Eventos en RabbitMQ pueden perderse si cola no es durable
   - Estado: CRÍTICO

### Frontend

1. **Deduplicación de Mensajes**

   - Historial cargado via HTTP: "Hola"
   - Mismo mensaje recibido via WebSocket: "Hola"
   - Usuario ve mensaje dos veces
   - Estado: CRÍTICO

2. **Optimistic Updates Sin Confirmación**

   - Usuario ve su mensaje inmediatamente
   - Si falla persistencia, usuario no lo sabe
   - Estado: CRÍTICO

3. **Falta "Enviando..." Indicator**

   - Usuario envía mensaje → aparece inmediatamente
   - Sin indicador visual de estado (enviando, error, enviado)
   - Estado: UX POBRE

4. **Sincronización de IsRead**

   - Backend guarda isRead en BD
   - Frontend nunca lo carga ni lo actualiza
   - Estado: NO IMPLEMENTADO

5. **Indicador "Escribiendo..."**

   - Otro usuario está escribiendo pero no hay feedback
   - Estado: NO IMPLEMENTADO

6. **JWT Decoding Sin Validación**
   - `JwtDecoder.decode()` no valida firma
   - Solo decodifica payload (riesgo de token modificado)
   - Estado: CRÍTICO DE SEGURIDAD

---

## Cambios en Configuración (.env)

### Nuevas Variables (FALTA IMPLEMENTAR)

```bash
# RabbitMQ (Fase 11)
RABBITMQ_URL=amqp://guest:guest@rabbitmq-service:5672/

# SendGrid (Fase 11)
SENDGRID_API_KEY=sg-xxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Opcional: Email fallback si SendGrid falla
FALLBACK_EMAIL_SMTP=
FALLBACK_EMAIL_USER=
FALLBACK_EMAIL_PASS=
```

**Estado**: NO DOCUMENTADO en archivo .env

---

## Stack Tecnológico (Fase 11)

### Backend

| Componente   | Versión     | Propósito                 | Fase |
| ------------ | ----------- | ------------------------- | ---- |
| Go           | 1.24+       | Lenguaje base             | 0    |
| PostgreSQL   | 15-alpine   | BD persistente            | 0    |
| Redis        | alpine      | Caché (OTP storage)       | 8    |
| MinIO        | latest      | Storage S3-compatible     | 2    |
| RabbitMQ     | 3.12-mgmt   | Message broker (NUEVO)    | 11   |
| SendGrid SDK | go-sendgrid | Email provider (NUEVO)    | 11   |
| AMQP Driver  | amqp091-go  | Conexión RabbitMQ (NUEVO) | 11   |

### Frontend

| Componente             | Versión | Propósito                | Fase |
| ---------------------- | ------- | ------------------------ | ---- |
| Flutter                | 3.24+   | Framework UI             | 5    |
| Dart                   | 3.10+   | Lenguaje                 | 5    |
| flutter_bloc           | latest  | State management (NUEVO) | 11   |
| jwt_decoder            | latest  | JWT parsing (NUEVO)      | 11   |
| web_socket_channel     | latest  | WebSocket client (NUEVO) | 4,10 |
| Dio                    | latest  | HTTP client              | 5    |
| flutter_secure_storage | latest  | Token storage            | 5    |

---

## Flujo End-to-End (Fase 11)

### Scenario: Usuario A envía mensaje a Usuario B (con persistencia)

```
┌─────────────────────────────────────────────────────────────────┐
│ CLIENTE A (Flutter App)                                         │
├─────────────────────────────────────────────────────────────────┤
│ 1. Usuario abre chat con Usuario B                              │
│    → ChatBloc emite InitChat(matchId=123)                       │
│                                                                  │
│ 2. ChatRepository.getHistory(123)                               │
│    → HTTP GET /matches/123/messages                             │
│    → Con JWT token en header                                    │
└─────────────────────────────────────────────────────────────────┘
                         ↓ HTTP
        ┌─────────────────────────────────────────┐
        │ BACKEND (Go)                            │
        ├─────────────────────────────────────────┤
        │ AuthMiddleware: Valida JWT              │
        │ SocialHandler.GetChatHistory:           │
        │   SELECT * FROM messages               │
        │   WHERE match_id = 123                  │
        │   ORDER BY created_at ASC               │
        │   LIMIT 100                             │
        └─────────────────────────────────────────┘
                         ↓ HTTP
┌─────────────────────────────────────────────────────────────────┐
│ CLIENTE A (Flutter App)                                         │
├─────────────────────────────────────────────────────────────────┤
│ 3. ChatLoaded emitido con historial [msg1, msg2, msg3]         │
│    UI renderiza mensajes previos                                │
│                                                                  │
│ 4. ChatRepository.connectToChat()                               │
│    → WebSocket connect con JWT en header                        │
│    → Espera mensajes nuevos                                     │
└─────────────────────────────────────────────────────────────────┘
                         ↓ WebSocket
        ┌─────────────────────────────────────────┐
        │ BACKEND (Go)                            │
        ├─────────────────────────────────────────┤
        │ WSHandler.HandleConnections:            │
        │   Registra cliente en hub                │
        │   Espera mensajes incoming              │
        └─────────────────────────────────────────┘
                    ↑                    ↓
            WebSocket (ws)       WebSocket (ws)
                    ↓                    ↑
┌─────────────────────────────────────────────────────────────────┐
│ CLIENTE A (Flutter App)                                         │
├─────────────────────────────────────────────────────────────────┤
│ 5. Usuario escribe "Hola, ¿cómo estás?"                         │
│    → ChatBloc emite SendMessageEvent("Hola, ¿cómo estás?")     │
│                                                                  │
│ 6. Optimistic Update:                                           │
│    - ChatRepository.sendMessage(123, "Hola...")                │
│    - Crea ChatMessage local con isMe=true                      │
│    - Emite ChatLoaded [msg1, msg2, msg3, mi_msg]               │
│    → Mensaje aparece inmediatamente en UI (0ms)                │
│                                                                  │
│ 7. WebSocket.sink.add('{match_id: 123, content: "Hola..."}')   │
└─────────────────────────────────────────────────────────────────┘
                         ↓ WebSocket
        ┌─────────────────────────────────────────┐
        │ BACKEND (Go)                            │
        ├─────────────────────────────────────────┤
        │ WSHandler.HandleConnections:            │
        │   1. conn.ReadJSON(&IncomingMessage)    │
        │   2. chatService.SaveMessage(...)       │
        │      - Valida forbiddenContent          │
        │      - Checa Match.status == accepted   │
        │      - INSERT INTO messages             │
        │      → ¡PERSISTE EN BD!                 │
        │   3. hub.broadcast <- message           │
        │                                          │
        │ 4. Hub.broadcast recibe mensaje         │
        │    → Itera sobre clientes conectados    │
        │    → Envía a todos en el match          │
        └─────────────────────────────────────────┘
                         ↓ WebSocket
┌─────────────────────────────────────────────────────────────────┐
│ CLIENTE B (Flutter App)                                         │
├─────────────────────────────────────────────────────────────────┤
│ 8. WebSocket.stream recibe mensaje del server                   │
│    → ChatBloc agrega _ReceiveMessageEvent(newMsg)              │
│                                                                  │
│ 9. ChatLoaded emitido con:                                      │
│    [msg1, msg2, msg3, mensaje_de_A]                            │
│    → Mensaje aparece en pantalla de B                           │
└─────────────────────────────────────────────────────────────────┘
```

**Timing**:

- Cliente A: 0ms (optimistic update)
- Cliente B: ~50-100ms (red trip + WebSocket broadcast)
- Persistencia BD: ~30ms (INSERT execute)
- **Garantía**: Si servidor reinicia, mensaje sobrevive en Postgres

---

## Propuestas de Corrección (Para Fases Futuras)

### Alta Prioridad (Breaking)

1. **Agregar RabbitMQ a docker-compose.yml**

   - Efecto: RabbitMQ no funciona sin esto
   - Esfuerzo: 10 líneas YAML
   - Prioridad: CRÍTICA

2. **Implementar Reintento Exponencial en EmailWorker**

   - Efecto: Emails no se pierden en fallos transitorios
   - Esfuerzo: 50 líneas Go (retry logic + backoff)
   - Prioridad: ALTA

3. **Agregar Deduplicación en ChatBloc**

   - Efecto: Evitar mensajes duplicados
   - Esfuerzo: 30 líneas Dart (Set<int> de message IDs)
   - Prioridad: ALTA

4. **Implementar "Enviando..." Indicator**
   - Efecto: UX clara sobre estado del mensaje
   - Esfuerzo: 100 líneas Dart + estado new
   - Prioridad: MEDIA

### Media Prioridad (Importante)

5. **Agregar Circuit Breaker a EmailWorker**

   - Efecto: Evitar retry infinito si SendGrid está caído
   - Esfuerzo: 80 líneas Go (circuit breaker pattern)
   - Prioridad: MEDIA

6. **Implementar Graceful Shutdown**

   - Efecto: Evitar pérdida de eventos en restart
   - Esfuerzo: 50 líneas Go (signal handling)
   - Prioridad: MEDIA

7. **Validar JWT Signature en Frontend**
   - Efecto: Mejorar seguridad (validar token no modificado)
   - Esfuerzo: 20 líneas Dart (usar lib con verificación)
   - Prioridad: SEGURIDAD

### Baja Prioridad (Nice to Have)

8. **Indicador "Escribiendo..."**

   - Efecto: Feedback UX mejorado
   - Esfuerzo: 150 líneas (backend + frontend)
   - Prioridad: BAJA

9. **Marcar Mensajes como "Leído"**

   - Efecto: Saber si otro usuario vio el mensaje
   - Esfuerzo: 200 líneas (backend + frontend)
   - Prioridad: BAJA

10. **Templates HTML para Emails**
    - Efecto: Emails con mejor formato
    - Esfuerzo: 100 líneas Go + CSS
    - Prioridad: BAJA

---

## Resumen de Estado (Fase 11)

| Componente             | Estado            | % Completo | Blockers             |
| ---------------------- | ----------------- | ---------- | -------------------- |
| RabbitMQ Integration   | INCOMPLETO        | 40%        | No en docker-compose |
| SendGrid Integration   | INCOMPLETO        | 70%        | No en .env           |
| EmailWorker            | INCOMPLETO        | 60%        | Sin reintento        |
| OTPService (Async)     | INCOMPLETO        | 80%        | Fallback es débil    |
| ChatRepository (FE)    | INCOMPLETO        | 75%        | Deduplicación falta  |
| ChatBloc (FE)          | INCOMPLETO        | 65%        | Sin indicadores      |
| ChatMessage Model (FE) | INCOMPLETO        | 60%        | fromJson incomplete  |
| docker-compose.yml     | INCOMPLETO        | 50%        | Falta RabbitMQ       |
| Configuration (.env)   | INCOMPLETO        | 30%        | No documentado       |
| **FASE 11 TOTAL**      | **EN DESARROLLO** | **60%**    | **INESTABLE**        |

---

## Conclusión

Fase 11 es un paso importante hacia una arquitectura escalable event-driven, pero está **parcialmente completada e inestable**. Los componentes principales existen pero les faltan:

1. Infraestructura completa (RabbitMQ en docker-compose)
2. Error handling robusto (reintento, circuit breaker)
3. Detalles frontend (deduplicación, indicadores)
4. Configuración integral (.env variables)
5. Graceful shutdown

**NO RECOMENDADO para producción ni para integración en rama principal hasta que se resuelvan los problemas críticos.**

Usar como referencia para aprender arquitectura event-driven, pero esperar a Fase 11.1+ para versión estable.
