# Fase 16: Notificaciones Push, Sistema Híbrido Tiempo Real y Inteligencia Online/Offline

## Introducción

La Fase 16 documenta Etapa 12, que completa la arquitectura de comunicación en tiempo real agregando notificaciones push para usuarios offline. Etapa 12 transforma PAWS de un sistema que solo funciona cuando el usuario está activo en la app a un sistema que alcanza usuarios en cualquier momento, implementando la experiencia familiar de apps como WhatsApp: mensajes instantáneos para usuarios presentes, notificaciones push para usuarios ausentes.

**Objetivos de Etapa 12**:

1. Implementar detección automática Online/Offline en el Hub
2. Crear flujo de notificaciones push mediante Firebase Cloud Messaging (FCM)
3. Capturar y almacenar tokens FCM de dispositivos
4. Implementar agrupación inteligente de notificaciones para mejorar UX
5. Desacoplar la lógica de push del servidor principal mediante RabbitMQ
6. Garantizar entrega de mensajes sin importar estado del usuario

## Arquitectura General - Flujo de Datos

```
┌─────────────────────────────────────────────────────────────────────┐
│ ETAPA 12: Notificaciones Push & Detección Online/Offline           │
└─────────────────────────────────────────────────────────────────────┘

CASO 1: Usuario ONLINE (App Abierta, WebSocket Conectado)
─────────────────────────────────────────────────────────────────

Usuario A (App Abierta)           Hub                    User B (App Abierta)
   │                              │                          │
   ├─ Lee mensaje                 │                          │
   ├─ Envía por WebSocket ─────────→ handleMessage()        │
   │                              ├─ Persiste en BD         │
   │                              ├─ Busca clients[B]       │
   │                              ├─ ENCONTRADO (online)   │
   │                              └─ Envía WebSocket ──────→ Recibe (0ms latencia)
   │                              │                          │
   └─ Recibe confirmación ◄───────┘                          │
     (ID real, timestamp)                                    │

CASO 2: Usuario OFFLINE (App Cerrada, Sin WebSocket)
─────────────────────────────────────────────────────────────────

User A (App Abierta)    Hub              RabbitMQ        Firebase        User B (App Cerrada)
   │                     │                   │               │                │
   ├─ Envía mensaje ────→ handleMessage()   │               │                │
   │                     ├─ Persiste en BD  │               │                │
   │                     ├─ Busca clients[B]│               │                │
   │                     ├─ NO ENCONTRADO   │               │                │
   │                     ├─ sendPush() ────→ Publica evento │                │
   │                     │                   │               │                │
   │                     │                   ├─ Queue       │                │
   │                     │                   │  'push_noti' │                │
   │                     │                   │               │                │
   │                     │           NotificationConsumer   │                │
   │                     │                   ├─ Lee evento  │                │
   │                     │                   ├─ Query: FCM  │                │
   │                     │                   ├─ token de BD │                │
   │                     │                   └─ fcmClient   │                │
   │                     │                      .Send() ───→ Publica a       │
   │                     │                                    Google         │
   │                     │                                      │            │
   │                     │                                      ├─ Cloud      │
   │                     │                                      │ Messaging  │
   │                     │                                      │            │
   │                     │                                      └────────────→ Notificación
   │                     │                                                    en barra
   │                     │                                                    (segundos)
   │                     │                                                    │
   │                     │                                                    ├─ Usuario
   │                     │                                                    │ toca
   │                     │                                                    └─ App abre
   │                     │                                                    (InitChat)
   │                     │
   └─ Confirmación ◄─────┘
     (ID real, timestamp)
```

## Backend: Componentes Clave

### 1. Domain: User con Token FCM

**internal/core/domain/user.go**

```go
type User struct {
    gorm.Model

    // Campos existentes...
    Name  string
    Email string
    Role  string
    IsVerified bool
    IsBanned bool
    PhotoURL string
    Bio      string
    Phone    string

    // NUEVO EN ETAPA 12: Token Firebase Cloud Messaging
    // Se actualiza cada vez que el usuario inicia sesión
    // Permite que Firebase envíe notificaciones push
    FCMToken string `json:"fcm_token"`
}
```

Significado: Cada usuario tiene un token único por dispositivo. Si instala la app en 2 teléfonos, tendrá 2 tokens diferentes. El último inicio de sesión sobrescribe el anterior (patrón común en apps).

### 2. NotificationEvent Model

**internal/core/services/match_service.go** (o service file dedicado)

```go
// Estructura genérica para eventos de notificación
type NotificationEvent struct {
    UserID uint   `json:"user_id"`      // Destinatario
    Title  string `json:"title"`        // "Nuevo Mensaje", "Match Aceptado", etc
    Body   string `json:"body"`         // Contenido de la notificación
    Type   string `json:"type"`         // "message", "match", "review", etc
}
```

Extensible: Cada `Type` puede llevar payload diferente, permitiendo futuros tipos como:

- `"match_accepted"`: Título "Match Aceptado", Body con nombre del rescatista
- `"review_pending"`: Título "Pendiente Reseña", Body con nombre del adoptante
- `"message"`: Título "Nuevo Mensaje", Body con fragmento del mensaje

### 3. Hub Mejorado: Enrutamiento Dual

**internal/transport/http/hub.go**

El Hub ahora detecta si el usuario está online consultando su mapa de clientes. Este mapeo es lo que diferencia Etapa 12 de Etapa 11:

```go
func (h *Hub) handleMessage(sender *Client, msgBytes []byte) {
    // PASOS 1-3: Parsear, guardar, preparar respuesta (como Etapa 11)
    var input InputMessage
    if err := json.Unmarshal(msgBytes, &input); err != nil {
        return
    }

    savedMsg, receiverID, err := h.chatService.SaveMessage(
        input.MatchID,
        sender.userID,
        input.Content,
    )
    if err != nil {
        sender.sendJSON("error", map[string]string{"message": err.Error()})
        return
    }

    response := OutputMessage{
        Type:    "new_message",
        Payload: savedMsg,
    }

    // CONFIRMACIÓN REMITENTE
    sender.sendJSON(response.Type, response.Payload)

    // ENRUTAMIENTO DUAL: LA CLAVE DE ETAPA 12
    // =====================================

    // Verificar: ¿Está el destinatario en el mapa de clientes conectados?
    if receiver, isOnline := h.clients[receiverID]; isOnline {
        // RAMA 1: ONLINE - Envío instantáneo por WebSocket
        // ├─ Latencia: <50ms
        // ├─ Confiabilidad: Cercana a 100% si connection es estable
        // └─ User experience: Mensaje aparece al instante
        receiver.sendJSON(response.Type, response.Payload)
        log.Printf("Mensaje enviado ONLINE a usuario %d vía WebSocket", receiverID)
    } else {
        // RAMA 2: OFFLINE - Envío diferido por Push Notification
        // ├─ Latencia: 2-10 segundos (depende de Google)
        // ├─ Confiabilidad: Depende de FCM, generalmente >95%
        // └─ User experience: Notificación en barra de estado
        h.sendPushNotification(receiverID, sender.userID, input.Content)
        log.Printf("Usuario %d offline. Notificación encolada para Firebase.", receiverID)
    }
}
```

**Garantía**: El mensaje se entrega en ambos casos:

- Online: Por WebSocket instantáneo
- Offline: Por Push Notification cuando conecte el dispositivo a internet

### 4. Método sendPushNotification

```go
func (h *Hub) sendPushNotification(receiverID, senderID uint, content string) {
    // Validación 1: ¿Hay RabbitMQ disponible?
    if h.mqClient == nil {
        log.Printf("RabbitMQ no disponible. Push para usuario %d no se enviará.", receiverID)
        return
    }

    // Validación 2: ¿El contenido es demasiado largo?
    maxBodyLength := 240  // FCM limita a 240 caracteres típicamente
    bodyTruncated := content
    if len(bodyTruncated) > maxBodyLength {
        bodyTruncated = bodyTruncated[:maxBodyLength] + "..."
    }

    // Construir evento
    event := services.NotificationEvent{
        UserID: receiverID,
        Title:  "Nuevo Mensaje",  // Genérico en MVP (podrías mejorar con nombre del remitente)
        Body:   bodyTruncated,
        Type:   "message",
    }

    // Serializar a JSON
    body, err := json.Marshal(event)
    if err != nil {
        log.Printf("Error serializando evento push: %v", err)
        return
    }

    // Publicar a RabbitMQ
    // Nota: La cola "push_notifications" es escuchada por NotificationConsumer
    err = h.mqClient.Publish("push_notifications", body)
    if err != nil {
        log.Printf("Error publicando a RabbitMQ: %v", err)
    } else {
        log.Printf("Evento push encolado para usuario %d", receiverID)
    }
}
```

**Punto Importante**: El error de envío a RabbitMQ no detiene la operación. El mensaje ya está en BD, así que no se pierde. Es graceful degradation: si RabbitMQ no está disponible, la app sigue funcionando (WebSocket seguirá entregando mensajes a usuarios online).

### 5. NotificationHandler: Endpoint para Tokens

**internal/transport/http/notification_handler.go**

```go
type NotificationHandler struct {
    userService *services.UserService
}

type TokenRequest struct {
    Token string `json:"token" binding:"required"`
}

func NewNotificationHandler(u *services.UserService) *NotificationHandler {
    return &NotificationHandler{userService: u}
}

func (h *NotificationHandler) UpdateToken(c *gin.Context) {
    // PASO 1: Extraer userID del JWT
    userIDVal, _ := c.Get("userID")
    var userID uint

    // Conversión segura (JWT típicamente envía float64)
    switch v := userIDVal.(type) {
    case float64:
        userID = uint(v)
    case uint:
        userID = v
    default:
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
        return
    }

    // PASO 2: Parsear token del request body
    var req TokenRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Token requerido"})
        return
    }

    if req.Token == "" {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Token vacío"})
        return
    }

    // PASO 3: Guardar en BD
    err := h.userService.UpdateFCMToken(userID, req.Token)
    if err != nil {
        log.Printf("Error actualizando token FCM: %v", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Error guardando token"})
        return
    }

    log.Printf("Token FCM actualizado para usuario %d (primeros 20 chars: %s)",
        userID, req.Token[:20])
    c.JSON(http.StatusOK, gin.H{
        "message": "Token FCM actualizado",
        "user_id": userID,
    })
}
```

### 6. UserService: Persistencia del Token

**internal/core/services/user_service.go**

```go
func (s *UserService) UpdateFCMToken(userID uint, token string) error {
    // UPDATE users SET fcm_token = $1 WHERE id = $2
    return s.db.Model(&domain.User{}).
        Where("id = ?", userID).
        Update("fcm_token", token).
        Error
}
```

Simple pero efectivo. La BD ahora tiene el token más reciente de cada usuario.

### 7. NotificationConsumer: Worker de Firebase

**internal/core/workers/notification_worker.go**

Este es el componente más importante. Es un goroutine separado que:

1. Escucha la cola RabbitMQ "push_notifications"
2. Para cada evento, busca el token FCM del usuario en BD
3. Envía mediante Firebase Cloud Messaging
4. Configura agrupación inteligente de notificaciones

```go
package workers

import (
    "context"
    "encoding/json"
    "log"
    "os"

    firebase "firebase.google.com/go"
    "firebase.google.com/go/messaging"
    "google.golang.org/api/option"

    rabbit "github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
    "github.com/RicketyMajor/PAWS-2.0/internal/core/services"
    "github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
    "gorm.io/gorm"
)

// StartNotificationConsumer inicia el worker de notificaciones push
func StartNotificationConsumer(mq *rabbit.RabbitMQClient, db *gorm.DB) {
    // PASO 1: Configurar Firebase
    projectID := os.Getenv("FIREBASE_PROJECT_ID")
    if projectID == "" {
        log.Println("ADVERTENCIA: FIREBASE_PROJECT_ID no configurado. Push notifications desactivadas.")
        return
    }

    conf := &firebase.Config{ProjectID: projectID}
    opt := option.WithCredentialsFile("firebase-service-account.json")

    app, err := firebase.NewApp(context.Background(), conf, opt)
    if err != nil {
        log.Printf("Error inicializando Firebase App: %v", err)
        return
    }

    fcmClient, err := app.Messaging(context.Background())
    if err != nil {
        log.Printf("Error obteniendo Messaging Client: %v", err)
        return
    }

    log.Println("✓ NotificationConsumer iniciado (escuchando RabbitMQ)")

    // PASO 2: Conectar a RabbitMQ
    ch := mq.GetChannel()

    // Declarar cola por seguridad (idempotente)
    _, err = ch.QueueDeclare(
        "push_notifications",  // nombre
        true,                  // durable: survive RabbitMQ restart
        false,                 // auto-delete
        false,                 // exclusive
        false,                 // no-wait
        nil,                   // args
    )
    if err != nil {
        log.Printf("Error declarando cola push_notifications: %v", err)
        return
    }

    // PASO 3: Consumir mensajes
    msgs, err := ch.Consume(
        "push_notifications",
        "",     // consumer tag (auto-generated)
        false,  // auto-ack: falso, hacemos ack manual
        false,  // exclusive
        false,  // no-local
        false,  // no-wait
        nil,    // args
    )
    if err != nil {
        log.Printf("Error consumiendo: %v", err)
        return
    }

    // PASO 4: Procesar mensajes en goroutine
    go func() {
        for d := range msgs {
            // Decodificar evento
            var event services.NotificationEvent
            if err := json.Unmarshal(d.Body, &event); err != nil {
                log.Printf("Error decodificando evento push: %v", err)
                d.Ack(false)
                continue
            }

            log.Printf("Procesando push para usuario %d", event.UserID)

            // Buscar usuario y su token FCM
            var user domain.User
            if err := db.Select("fcm_token").
                First(&user, event.UserID).Error; err != nil {
                log.Printf("Usuario %d no encontrado o sin token", event.UserID)
                d.Ack(false)
                continue
            }

            // Validar token no vacío
            if user.FCMToken == "" {
                log.Printf("Usuario %d sin token FCM almacenado", event.UserID)
                d.Ack(false)
                continue
            }

            // Configurar Android Config con TAG para agrupación
            var androidConfig *messaging.AndroidConfig

            if event.Type == "message" {
                androidConfig = &messaging.AndroidConfig{
                    Priority: "high",
                    Notification: &messaging.AndroidNotification{
                        // TAG: Agrupa notificaciones de mismo tipo
                        // Sin esto, cada notificación es separada
                        // Con esto: "3 mensajes nuevos" en 1 notificación
                        Tag:   "chat_group",
                        Color: "#E91E63",  // Color rosado PAWS
                    },
                }
            } else if event.Type == "match" {
                androidConfig = &messaging.AndroidConfig{
                    Priority: "high",
                    Notification: &messaging.AndroidNotification{
                        Tag:   "matches_group",
                        Color: "#FF5722",  // Naranja para matches
                    },
                }
            }
            // Extensible para otros tipos...

            // Enviar a Firebase
            resp, err := fcmClient.Send(context.Background(), &messaging.Message{
                Token: user.FCMToken,
                Notification: &messaging.Notification{
                    Title: event.Title,
                    Body:  event.Body,
                },
                Android: androidConfig,
                Data: map[string]string{
                    "type": event.Type,
                    "timestamp": time.Now().String(),
                },
            })

            if err != nil {
                log.Printf("Error enviando a FCM: %v", err)
                d.Nack(false, true)  // Requeue: reintentar después
            } else {
                log.Printf("Push enviado a usuario %d (response: %s)", event.UserID, resp)
                d.Ack(false)  // Confirmar consumo
            }
        }
    }()
}
```

**Puntos Clave**:

1. **Android Notification Tags**: La línea `Tag: "chat_group"` es mágica. Hace que múltiples notificaciones se agrupen. Usuarios finales ven "3 mensajes nuevos" en lugar de 3 notificaciones saturando la barra.

2. **Manual ACKs**: No usamos `auto-ack: true`. Hacemos ack manual solo después de enviar a Firebase. Si el worker se cae, RabbitMQ reintentar mensajes no procesados.

3. **Requeue Logic**: Si FCM falla, `d.Nack(false, true)` reintentar el mensaje después. Así no se pierden notificaciones por fallos transitorios.

4. **Priority: "high"**: Android muestra notificación inmediatamente (no en background quiet period).

## Frontend: Captura de Token FCM

### 1. Configuración en main.dart

```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// --- HANDLER GLOBAL PARA NOTIFICACIONES EN BACKGROUND ---
// Se ejecuta incluso cuando la app está cerrada
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    print("Notificación en Background: ${message.messageId}");
    print("Título: ${message.notification?.title}");
    print("Cuerpo: ${message.notification?.body}");

    // Aquí podrías:
    // - Actualizar una tabla local de notificaciones
    // - Sincronizar chat con servidor
    // - Reproducir sonido customizado
    // (Pero debes mantenerlo rápido, máx 30 segundos)
}

void main() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Inicializar Firebase
    try {
        await Firebase.initializeApp();

        // 2. Registrar handler para notificaciones en background
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

        log("Firebase inicializado correctamente");
    } catch (e) {
        print("Error inicializando Firebase: $e");
        // No es crítico, continúa sin notificaciones
    }

    runApp(const PawsApp());
}

class PawsApp extends StatefulWidget {
    const PawsApp({super.key});

    @override
    State<PawsApp> createState() => _PawsAppState();
}

class _PawsAppState extends State<PawsApp> {
    @override
    void initState() {
        super.initState();
        _setupFirebaseMessaging();
    }

    void _setupFirebaseMessaging() async {
        FirebaseMessaging messaging = FirebaseMessaging.instance;

        // 2. PEDIR PERMISOS (Android 13+)
        NotificationSettings settings = await messaging.requestPermission(
            alert: true,     // Mostrar notificación
            badge: true,     // Mostrar número en icono
            sound: true,     // Reproducir sonido
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
            print('Permisos de notificación CONCEDIDOS');

            // 3. OBTENER TOKEN (pero no enviarlo todavía, falta autenticación)
            String? token = await messaging.getToken();
            if (token != null) {
                print("FCM Token obtenido: ${token.substring(0, 20)}...");
            }
        } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
            print('Permisos provisional (solo en pruebas)');
        } else {
            print('Permisos de notificación RECHAZADOS');
        }

        // 4. ESCUCHAR NOTIFICACIONES CUANDO APP ESTÁ ABIERTA
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
            print("Notificación mientras app abierta: ${message.notification?.title}");

            // Podrías mostrar dialog custom, toast, etc.
            // En vez de notificación del sistema
        });

        // 5. ESCUCHAR TAPS EN NOTIFICACIONES
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
            print("Usuario tocó notificación: ${message.notification?.title}");
            // Aquí navegar a chat, match, etc. según message.data
        });
    }

    @override
    Widget build(BuildContext context) {
        return MaterialApp(
            home: const LoginScreen(),
        );
    }
}
```

### 2. Envío del Token en LoginScreen

```dart
class LoginState extends State<LoginScreen> {
    @override
    Widget build(BuildContext context) {
        return BlocListener<LoginBloc, LoginState>(
            listener: (context, state) async {
                if (state is LoginSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Iniciando sesión...'),
                            backgroundColor: Colors.green,
                        ),
                    );

                    // --- NUEVA LÓGICA: GUARDAR TOKEN FCM ---
                    try {
                        // 1. Obtener token de Firebase
                        String? fcmToken = await FirebaseMessaging.instance.getToken();

                        if (fcmToken != null && mounted) {
                            // 2. Enviar al backend
                            await context.read<UserRepository>().saveDeviceToken(fcmToken);
                            print("Token FCM enviado al backend exitosamente");
                        }
                    } catch (e) {
                        // No bloqueamos login si esto falla
                        print("Error enviando token FCM: $e");
                    }

                    // 3. Navegar como siempre
                    if (!mounted) return;

                    final authRepo = context.read<AuthRepository>();
                    final token = await authRepo.getToken();

                    if (token != null) {
                        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
                        String role = decodedToken['role'] ?? 'adopter';

                        if (role == 'admin') {
                            Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => AdminDashboardScreen()),
                                (route) => false,
                            );
                        } else {
                            Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => MainLayoutScreen()),
                                (route) => false,
                            );
                        }
                    }
                }
            },
            child: // ... UI del login ...
        );
    }
}
```

### 3. UserRepository: saveDeviceToken

```dart
class UserRepository {
    final Dio _dio;
    final FlutterSecureStorage _storage;

    UserRepository({required Dio dio, required FlutterSecureStorage storage})
        : _dio = dio,
          _storage = storage;

    /// Enviar token FCM al backend
    Future<void> saveDeviceToken(String fcmToken) async {
        try {
            // Obtener opción con JWT
            final options = await _getAuthOptions();

            // POST /notifications/token con token
            final response = await _dio.post(
                '${ApiConstants.baseUrl}/notifications/token',
                data: {'token': fcmToken},
                options: options,
            );

            if (response.statusCode == 200 || response.statusCode == 201) {
                print("Token FCM guardado en servidor");
            } else {
                print("Error guardando token: ${response.statusCode}");
            }
        } on DioException catch (e) {
            print("Error de conexión enviando token: $e");
            // No relanzamos, la app continúa funcionando sin push notifications
        } catch (e) {
            print("Error inesperado: $e");
        }
    }

    /// Helper para obtener opciones de HTTP con JWT
    Future<Options> _getAuthOptions() async {
        final token = await _storage.read(key: 'jwt_token');
        return Options(
            headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
            },
        );
    }
}
```

## Flujos de Uso

### Flujo 1: Usuario Online Recibe Mensaje

```
Adoptante A (app abierta)
  ├─ Escribe "¿Cuándo nos vemos?"
  ├─ Envía por WebSocket
  │
Rescatista B (app abierta, WebSocket conectado)
  ├─ Hub detecta: clients[B] existe
  ├─ Envía por WebSocket directo
  └─ Mensaje aparece al instante en pantalla
```

Experiencia: Conversación fluida como WhatsApp web.

### Flujo 2: Usuario Offline Recibe Mensaje

```
Adoptante A (app abierta)
  ├─ Escribe "¿Cuándo nos vemos?"
  ├─ Envía por WebSocket
  │
Rescatista B (app cerrada)
  ├─ Hub detecta: clients[B] NO existe
  ├─ Llama sendPushNotification()
  │  └─ Publica a RabbitMQ "push_notifications"
  │     {UserID: B, Title: "Nuevo Mensaje", Body: "¿Cuándo..."}
  │
NotificationConsumer (worker separado)
  ├─ Lee evento de RabbitMQ
  ├─ Query: SELECT fcm_token FROM users WHERE id=B
  ├─ Obtiene: "efgiVWxyz..."
  ├─ fcmClient.Send(token, {Title, Body, AndroidConfig{Tag: "chat_group"}})
  │
Firebase Cloud Messaging
  ├─ Conecta con Google Play Services en dispositivo B
  ├─ Muestra notificación
  └─ Agrupa bajo TAG "chat_group" (si hay más, mostrará "2 mensajes nuevos")

Rescatista B (app cerrada)
  └─ Recibe notificación en barra
```

Experiencia: Notificación aparece en segundos (depende de internet del dispositivo).

### Flujo 3: Múltiples Mensajes Agrupados

```
Adoptante A envía: "Hola"
Rescatista B offline → Push 1 (Tag: "chat_group")

Adoptante A envía: "¿Estás?
Rescatista B offline → Push 2 (Tag: "chat_group")

Adoptante A envía: "Cuéntame sobre Max"
Rescatista B offline → Push 3 (Tag: "chat_group")

Resultado en notificación de B:
┌─────────────────────────┐
│ PAWS Adoptions          │
├─────────────────────────┤
│ Nuevos mensajes        │
│ • 3 mensajes nuevos     │
└─────────────────────────┘
```

Sin agrupación (sin Tag), aparecerían 3 notificaciones separadas.

## Configuración Requerida

### Backend: .env

```bash
# Firebase
FIREBASE_PROJECT_ID=paws-app-3187d

# RabbitMQ
ENABLE_ASYNC_FEATURES=true
RABBITMQ_HOST=rabbitmq      # En Docker: servicio RabbitMQ
RABBITMQ_PORT=5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# Credenciales: archivo firebase-service-account.json debe existir
# Descargado desde Google Cloud Console
```

### docker-compose.yml: RabbitMQ

```yaml
rabbitmq:
  image: rabbitmq:3.12-alpine
  container_name: paws-rabbitmq
  restart: always
  ports:
    - "5672:5672" # AMQP
    - "15672:15672" # Management UI (http://localhost:15672)
  environment:
    RABBITMQ_DEFAULT_USER: guest
    RABBITMQ_DEFAULT_PASS: guest
  volumes:
    - rabbitmq_data:/var/lib/rabbitmq
```

### Frontend: pubspec.yaml

```yaml
dependencies:
  firebase_core: ^2.24.0
  firebase_messaging: ^14.6.0
  flutter_bloc: ^8.1.3
  dio: ^5.3.1
  # ... resto de dependencias ...
```

### Inicialización en main.go

```go
func main() {
    // ... setup previo ...

    // Conectar a RabbitMQ
    var mqClient *messaging.RabbitMQClient
    if os.Getenv("ENABLE_ASYNC_FEATURES") == "true" {
        mqClient, _ = messaging.ConnectRabbitMQ(rabbitURL)
    }

    // Iniciar workers
    if mqClient != nil {
        workers.StartEmailConsumer(mqClient, emailClient)        // Etapa 10
        workers.StartNotificationConsumer(mqClient, database.DB)  // Etapa 12
        log.Println("Workers iniciados: Email + Notifications")
    }

    // Hub con inyección de RabbitMQ
    hub := httpTransport.NewHub(chatService, mqClient)
    go hub.Run()

    // ... resto de setup ...
}
```

## Debugging & Monitoreo

### Logs Importantes

```
Backend:
├─ "Conectado a RabbitMQ" → RabbitMQ disponible
├─ "Usuario %d offline. Notificación encolada" → Mensaje divergido a push
├─ "Worker de Notificaciones Push iniciado" → NotificationConsumer corriendo
├─ "Push enviado a usuario %d" → Firebase aceptó notificación
└─ "Error enviando a FCM" → Firebase rechazó (token expirado, etc)

Firebase Console:
├─ Dashboard muestra notificaciones enviadas
├─ Error log si hay problemas con tokens
└─ Analytics de entrega (si está habilitado)
```

### RabbitMQ Management UI

```
http://localhost:15672
Username: guest
Password: guest

Verificar:
├─ "push_notifications" cola existe
├─ Mensajes encolados (si hay backlog)
├─ NotificationConsumer conectado como consumer
└─ Tasa de entrega
```

### Testing Manual

```bash
# Terminal 1: Conectar como usuario A (online)
wscat -c "ws://localhost:8080/api/v1/ws" \
  -H "Authorization: Bearer TOKEN_A"

# Terminal 2: Conectar como usuario B (online)
wscat -c "ws://localhost:8080/api/v1/ws" \
  -H "Authorization: Bearer TOKEN_B"

# Desde Terminal 1: Enviar mensaje
{"match_id": 1, "content": "Hola!"}

# Terminal 2 debe recibir:
{"type": "new_message", "payload": {...}}

# Ahora cerrar app de B (desconectar Terminal 2)
# Desde Terminal 1: Enviar otro mensaje
{"match_id": 1, "content": "¿Estás ahí?"}

# Verificar en RabbitMQ Management:
# - Cola "push_notifications" debe tener 1 mensaje
# Ver en logs:
# - "Usuario B offline. Notificación encolada"
# - NotificationConsumer debe procesar y enviar a Firebase
```

## Mejoras Futuras

1. **Incremento de Badge Count**: Mostrar número en icono de app
2. **Deep Linking**: Tocar notificación abre chat específico
3. **Typing Indicator**: Enviar evento "typing" que no requiere persistencia
4. **Read Receipts**: Notificar al remitente cuando leyó el mensaje
5. **Custom Sounds**: Sonido diferente para notificaciones de chat vs matches
6. **Retry Logic**: Reintentos con backoff exponencial en caso de fallo FCM
7. **Analytics**: Contar entregas exitosas vs fallos, latencias
8. **Multi-Device**: Gestionar múltiples tokens por usuario (1 por dispositivo)

## Resumen de Cambios

| Componente           | Cambio                                   | Impacto                    |
| -------------------- | ---------------------------------------- | -------------------------- |
| Hub                  | Agrega mqClient, detecta online/offline  | Enrutamiento dual          |
| Hub.handleMessage    | Condicional if receiver, isOnline        | Desvía offline a push      |
| UserService          | Nuevo método UpdateFCMToken()            | Persiste tokens            |
| User Domain          | Nuevo campo FCMToken                     | Almacena para cada usuario |
| NotificationHandler  | Nuevo endpoint POST /notifications/token | Captura tokens             |
| NotificationConsumer | Nuevo worker escuchando RabbitMQ         | Envía a Firebase           |
| LoginScreen          | Obtiene y envía token                    | Transparente, sin UI       |
| UserRepository       | saveDeviceToken()                        | Abstracción HTTP           |
| main.dart            | Firebase.initializeApp(), handlers       | Setup global               |

## Referencias

- Firebase Cloud Messaging: https://firebase.google.com/docs/cloud-messaging
- Android Notifications Tags: https://developer.android.com/develop/ui/views/notifications/group
- Firebase Admin SDK Go: https://pkg.go.dev/firebase.google.com/go/v4
- RabbitMQ Go Client: https://github.com/rabbitmq/amqp091-go
- FCM Payload Limits: https://firebase.google.com/docs/cloud-messaging/concept-options#payload
