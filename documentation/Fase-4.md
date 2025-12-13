# Fase 4: Sistema de Chat Distribuido y Seguridad en Tiempo Real

## Introducción

La Fase 4 implementa el corazón comunicacional de PAWS: un sistema de chat escalable, distribuido y seguro. Esta fase representa un salto arquitéctonico significativo, pasando de una arquitectura monolítica a una arquitectura de sistemas distribuidos. Se introduce WebSocket para comunicación en tiempo real persistente, Redis Pub/Sub como megáfono global para múltiples servidores, y un sistema activo de seguridad que inspecciona mensajes en tiempo real (R-SEC-05).

## Objetivos de la Fase 4

1. Implementar servidor WebSocket con soporte para conexiones persistentes
2. Crear arquitectura distribuida usando Redis Pub/Sub
3. Manejar múltiples clientes concurrentes usando Goroutines
4. Implementar filtro de palabras prohibidas en tiempo real (R-SEC-05)
5. Mantener la sincronización entre múltiples instancias del servidor
6. Implementar heartbeat para mantener conexiones vivas
7. Optimizar throughput de mensajes en tiempo real

## Stack Tecnológico Actualizado

### Backend

- **Lenguaje**: Go 1.24.0
- **Framework Web**: Gin v1.11.0
- **WebSocket**: gorilla/websocket v1.5.3
- **Redis Client**: github.com/redis/go-redis/v9
- **Patrón**: Redis Pub/Sub (Publicador-Suscriptor)

### Infraestructura

- **Redis**: Servicio de publicación-suscripción global
- **WebSocket**: Protocolo TCP persistente (en lugar de HTTP petición-respuesta)
- **Goroutines**: Concurrencia ligera de Go para I/O no bloqueante

## Cambios en la Estructura del Proyecto

Comparando con Fase 3, la estructura ha evolucionado agregando componentes de comunicación en tiempo real:

```
PAWS-2.0/
├── cmd/
│   └── api/
│       └── main.go                    # (ACTUALIZADO: Inicializa Hub y rutas WebSocket)
├── internal/
│   ├── core/
│   │   ├── domain/
│   │   │   ├── user.go
│   │   │   └── pet.go
│   │   └── services/
│   │       ├── auth_service.go
│   │       ├── pet_service.go
│   │       ├── file_service.go
│   │       ├── identity_service.go
│   │       └── match_service.go       # (Sin cambios desde Fase 3)
│   ├── transport/
│   │   ├── http/
│   │   │   ├── auth_handler.go
│   │   │   ├── pet_handler.go
│   │   │   ├── upload_handler.go
│   │   │   ├── identity_handler.go
│   │   │   ├── match_handler.go
│   │   │   ├── ws_handler.go          # NUEVO: Handler WebSocket
│   │   │   └── middleware/
│   │   │       └── auth.go
│   │   └── websocket/                 # NUEVA carpeta: Lógica de chat
│   │       ├── client.go              # NUEVO: Cliente WebSocket
│   │       └── hub.go                 # NUEVO: Hub distribuido con Redis
│   └── platform/
│       └── database/
├── uploads/
├── docker-compose.yml
├── go.mod                             # (ACTUALIZADO: +redis, +websocket)
├── go.sum
├── .env
└── documentation/
    └── Fase-4.md                      # Este archivo
```

## Detalles Técnicos Implementados

### 1. Arquitectura de Sistemas Distribuidos

La clave de la Fase 4 es entender que transformamos el arquitecto de un solo servidor monolítico a un sistema que puede escalar horizontalmente:

#### Versión Monolítica (Fase 2-3):

```
Cliente A ──┐
             │─→ Servidor Go ←─┐
Cliente B ──┘                   │ (Almacenar clientes en memoria)
                                │
Cliente C ───────────────────────┘
```

Problema: Si el servidor cae, los 3 clientes pierden conexión.

#### Versión Distribuida (Fase 4):

```
Cliente A ──┐
             │─→ Servidor 1 ───┐
Cliente B ──┘                   │
                                │─→ Redis ←─┐
Cliente C ──┐                   │           │
             │─→ Servidor 2 ───┘           │
Cliente D ──┘                   ├──────────┘
                                │
Cliente E ──┐                   │
             │─→ Servidor 3 ───┘
Cliente F ──┘
```

**Ventajas**:

- Cliente A puede enviar mensaje que Servidor 1 publica en Redis
- Servidor 2 (sin Cliente A) escucha Redis y entrega a sus clientes
- Si Servidor 1 cae, Cliente A se reconecta a Servidor 2
- Escalabilidad horizontal: Agregar servidores es trivial

### 2. WebSocket: Del Protocolo HTTP a TCP Persistente

#### HTTP (Petición-Respuesta):

```
Cliente: GET /messages HTTP/1.1
         ↓ (conexión se cierra)
Servidor: HTTP/1.1 200 OK
          [respuesta]
         ↓ (conexión se cierra)
```

Problema: Chat en tiempo real requeriría polling constante (ineficiente).

#### WebSocket (Tubería Persistente):

```
Cliente ═══════════════════════ Servidor
        (conexión TCP abierta, ambos pueden enviar simultáneamente)
```

Beneficio: Bidireccional, bajo-latencia, eficiente.

### 3. Hub: El Cerebro del Sistema (websocket/hub.go)

```go
type Hub struct {
    Clients map[*Client]bool    // Registro de clientes conectados
    Broadcast chan []byte        // Canal para mensajes entrantes
    Register chan *Client        // Solicitudes de registro
    Unregister chan *Client      // Solicitudes de desregistro
    RedisClient *redis.Client    // Conexión a Redis
}
```

#### Función Run() - El Loop Principal:

```go
func (h *Hub) Run() {
    go h.subscribeToRedis()  // Escuchar Redis en paralelo

    for {
        select {
        case client := <-h.Register:
            h.Clients[client] = true

        case client := <-h.Unregister:
            delete(h.Clients, client)

        case message := <-h.Broadcast:
            // Publicar a Redis (clave del sistema distribuido)
            h.RedisClient.Publish(ctx, "paws_chat", message)
        }
    }
}
```

**Flujo Detallado**:

1. **Usuario A envía mensaje**:

   - WebSocket del Cliente A envía bytes al ReadPump
   - ReadPump valida (filtra malas palabras)
   - Envía a `h.Broadcast`

2. **Hub recibe en Broadcast**:

   - En lugar de enviar directo a clientes locales,
   - Publica en Redis: `PUBLISH paws_chat "mensaje de A"`

3. **Redis distribuye**:

   - Todos los Servidores escuchando `paws_chat` reciben
   - Incluso Servidor Go #1 (donde originó el mensaje)

4. **subscribeToRedis() recibe**:

   - Loop infinito escuchando el canal
   - Para cada mensaje, recorre todos los Clients locales
   - Envía a canal `client.Send`

5. **WritePump() entrega**:
   - Recibe del canal `Send`
   - Escribe al WebSocket real
   - Cliente ve el mensaje

### 4. Cliente WebSocket (websocket/client.go)

```go
type Client struct {
    Hub    *Hub
    Conn   *websocket.Conn
    Send   chan []byte       // Cola de salida
    UserID string            // ID del usuario
}
```

#### ReadPump - Lectura de Mensajes

```go
func (c *Client) ReadPump() {
    defer func() {
        c.Hub.Unregister <- c  // Limpiar registro
        c.Conn.Close()
    }()

    for {
        _, message, err := c.Conn.ReadMessage()
        if err != nil {
            break
        }

        // --- FILTRO R-SEC-05 ---
        if containsBadWords(message) {
            log.Printf("ALERTA: Usuario %s envió: %s", c.UserID, message)
            // Bloquear silencioso (no enviar a Hub)
            continue
        }

        // Si pasó validación, enviar al Hub
        c.Hub.Broadcast <- message
    }
}
```

**Puntos Clave**:

1. **SetReadLimit**: Limita tamaño de mensaje a 512 bytes

   - Previene ataques de memoria (DoS)

2. **SetReadDeadline**: Timeout para lectura

   - Detecta clientes desconectados

3. **SetPongHandler**: Responde a pings de servidor

   - Mantiene la conexión viva

4. **Filtro de Malas Palabras**: Inspección en tiempo real
   - `containsBadWords()` busca en array predefinido
   - `bytes.ToLower()` hace búsqueda case-insensitive
   - `bytes.Contains()` detecta substrings

#### WritePump - Escritura de Mensajes

```go
func (c *Client) WritePump() {
    ticker := time.NewTicker(pingPeriod)
    defer func() {
        ticker.Stop()
        c.Conn.Close()
    }()

    for {
        select {
        case message, ok := <-c.Send:
            if !ok {
                c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
                return
            }
            c.Conn.WriteMessage(websocket.TextMessage, message)

            // Optimización: batchar múltiples mensajes en un paquete TCP
            n := len(c.Send)
            for i := 0; i < n; i++ {
                w.Write([]byte{'\n'})
                w.Write(<-c.Send)
            }

        case <-ticker.C:
            // Heartbeat: mantener conexión viva
            c.Conn.WriteMessage(websocket.PingMessage, nil)
        }
    }
}
```

**Características Importantes**:

1. **Heartbeat (Ping/Pong)**:

   ```
   Servidor cada 54 segundos: "¿Estás ahí?"
   Cliente: "Sí, estoy aquí"
   ```

   Detecta clientes muertos (desconexiones no limpias)

2. **Batching de Mensajes**:

   - Si hay 5 mensajes en cola `Send`
   - Envía todos en 1 paquete TCP
   - Reduce overhead de red

3. **Manejo de Cierre**:
   - Si el Hub cierra el canal `Send`
   - Cliente recibe `ok = false`
   - Envía `CloseMessage` y termina

### 5. Filtro de Seguridad - Implementación R-SEC-05

```go
var badWords = [][]byte{
    []byte("tonto"),
    []byte("estafa"),
    []byte("maltrato"),
    []byte("falso"),
}

func containsBadWords(message []byte) bool {
    lowerMsg := bytes.ToLower(message)
    for _, word := range badWords {
        if bytes.Contains(lowerMsg, word) {
            return true
        }
    }
    return false
}
```

**Seguridad Implementada**:

1. **Inspección de Bytes**: Antes de que el mensaje llegue a Redis

   - ReadPump valida ANTES de `Hub.Broadcast`
   - Ningún servidor distribuido lo ve

2. **Case-Insensitive**: Normalización a minúsculas

   - Previene bypass: "TONTO", "ToNtO", etc.

3. **Substring Matching**: `bytes.Contains()`

   - Detecta palabras dentro de textos
   - Ejemplo: "eres un tonto" → bloqueado

4. **Shadowban Silencioso**:

   - Usuario NO recibe error
   - Solo log del lado del servidor
   - `continue` en ReadPump mata el mensaje

5. **Alerta del Sistema**: Mensaje al usuario
   ```go
   errorMessage := []byte("Mensaje bloqueado por Evil PAWS")
   select {
   case c.Send <- errorMessage:
   }
   ```
   - Usuario ve notificación sin saber qué pasó

### 6. Handler WebSocket (transport/http/ws_handler.go)

```go
type WSHandler struct {
    hub *websocket.Hub
}

func (h *WSHandler) HandleConnections(c *gin.Context) {
    // 1. Extraer UserID del JWT
    userIDFloat, _ := c.Get("userID")
    id := int(userIDFloat.(float64))
    userID := fmt.Sprintf("user_%d", id)

    // 2. Upgrade HTTP → WebSocket
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        log.Println("Error upgrading:", err)
        return
    }

    // 3. Crear cliente y registrar
    client := &websocket.Client{
        Hub:    h.hub,
        Conn:   conn,
        Send:   make(chan []byte, 256),
        UserID: userID,
    }
    client.Hub.Register <- client

    // 4. Iniciar goroutines de I/O
    go client.WritePump()   // Lectura de BD, escritura a socket
    go client.ReadPump()    // Lectura de socket, escritura a BD
}
```

**Puntos Clave**:

1. **Upgrader**:

   ```go
   var upgrader = gws.Upgrader{
       ReadBufferSize:  1024,
       WriteBufferSize: 1024,
       CheckOrigin: func(r *http.Request) bool {
           return true  // Permitir cualquier origen (CORS)
       },
   }
   ```

2. **Conversión de UserID**:

   - JWT devuelve float64: `1.0`
   - Convertimos a int: `1`
   - Formateamos a string: `"user_1"`

3. **Goroutines**:
   - `WritePump()`: Goroutine #1
   - `ReadPump()`: Goroutine #2
   - Ambas se ejecutan en paralelo
   - Go maneja el multiplexing internamente

### 7. Actualización de main.go

```go
// Crear Hub al startup
hub := websocket.NewHub()
go hub.Run()  // Iniciar en goroutine separada

// Crear handler
wsHandler := transport.NewWSHandler(hub)

// Registrar ruta WebSocket
chat := api.Group("/chat")
chat.Use(middleware.AuthMiddleware())
{
    chat.GET("/ws", wsHandler.HandleConnections)
}
```

**Por qué `go hub.Run()`?**:

- Hub.Run() es un loop infinito
- Si lo hacemos síncrono, bloquea el programa
- En una goroutine, corre en paralelo con el servidor HTTP

### 8. Actualización de go.mod

```
+ github.com/gorilla/websocket v1.5.3
+ github.com/redis/go-redis/v9
```

Nuevas dependencias para WebSocket y Redis.

## Flujos de Comunicación Completos

### Escenario 1: Chat Entre Dos Usuarios (Mismo Servidor)

```
Usuario A (Servidor 1)
    │ "Hola B"
    │ (WebSocket)
    ↓
Client.ReadPump()
    ├─ Validar (no malas palabras)
    │ ✓
    └─ Hub.Broadcast <- ["Hola B"]
       ↓
    Hub.Run() recibe Broadcast
       ├─ Redis.Publish("paws_chat", "Hola B")
       │  ↓
       └─→ Redis broadcasts a todos los subscribers
           ↓
    Hub.subscribeToRedis() recibe
       ├─ Para Cliente A: Send <- ["Hola B"]
       ├─ Para Cliente C: Send <- ["Hola B"]
       └─ Para Cliente D: Send <- ["Hola B"]
           ↓
    WritePump() de cada cliente
       │ WebSocket envío
       ↓
Usuario A: ve su propio mensaje
Usuario C: ve el mensaje de A
Usuario D: ve el mensaje de A
```

### Escenario 2: Chat Entre Usuarios (Servidores Diferentes)

```
Servidor 1 (Usuario A)          Servidor 2 (Usuario B)
────────────────────────        ──────────────────────

Usuario A: "Hola B"
    ↓ WebSocket
ReadPump() A
    │ ✓ pasa filtro
    ↓
Broadcast <- msg
    │ (local)
    ↓
Hub.Run() S1
    │ Publish Redis
    ↓
    └──────→ Redis ←──────────────────┐
             "Hola B"                   │
             ↑────────────────────────┐ │
                                      │ │
                                 Subscribe S2
                                    ↓
                            Hub.subscribeToRedis() S2
                                    │
                                    └─→ Send <- ["Hola B"]
                                        ↓
                                    WritePump() B
                                        │ WebSocket
                                        ↓
                                Usuario B: "Hola B"

(También, Sub S1 recibe su propio mensaje y lo envía a todos sus clientes locales)
```

### Escenario 3: Bloqueo de Mensaje Malicioso (R-SEC-05)

```
Usuario Malicioso
    │ "eres un tonto"
    │ (WebSocket)
    ↓
Client.ReadPump()
    ├─ containsBadWords() detects "tonto"
    │ ✗ FALLA VALIDACIÓN
    │
    ├─ log.Printf("ALERTA: User intentó...")
    │
    ├─ Send <- ["Mensaje bloqueado..."] (solo al usuario)
    │
    └─ continue (mata el mensaje)
       ↓
    (NO envía a Hub.Broadcast)
    (NO publica en Redis)
    (Mensaje muere aquí)

La comunidad nunca lo ve.
Solo hay un log del servidor como evidencia.
```

## Cambios Detectados desde Fase 3

| Componente        | Cambio                        | Impacto                      |
| ----------------- | ----------------------------- | ---------------------------- |
| **go.mod**        | +gorilla/websocket v1.5.3     | WebSocket protocol           |
| **go.mod**        | +redis/go-redis/v9            | Redis Pub/Sub                |
| **Nueva carpeta** | internal/transport/websocket/ | Lógica distribuida           |
| **Nuevo archivo** | websocket/client.go           | Cliente WebSocket individual |
| **Nuevo archivo** | websocket/hub.go              | Hub con Redis Pub/Sub        |
| **Nuevo archivo** | ws_handler.go                 | Endpoint WebSocket           |
| **main.go**       | hub := websocket.NewHub()     | Inicialización de Hub        |
| **main.go**       | go hub.Run()                  | Loop distribuido             |
| **main.go**       | chat routes                   | Endpoint /api/v1/chat/ws     |
| **Estructura**    | Goroutines ReadPump/WritePump | Concurrencia I/O             |
| **Estructura**    | Redis Pub/Sub                 | Escalabilidad horizontal     |

## Decisiones Arquitectónicas Importantes

### 1. Redis Pub/Sub vs Message Queue

**Redis Pub/Sub (Implementado)**:

- Fire-and-forget: Publica y olvida
- Bajo-latencia: Entrega inmediata
- Sin persistencia: Mensajes perdidos si no hay subscribers
- Ideal para: Chat en tiempo real

**Message Queue (RabbitMQ, Kafka)**:

- Con persistencia: Mensajes almacenados
- Garantía de entrega: Reintentos automáticos
- Mayor latencia
- Ideal para: Tareas críticas, auditoría

Elegimos Pub/Sub porque el chat no necesita garantía de entrega (si un usuario desconecta, no le importa perder un mensaje).

### 2. Goroutines vs Threads Tradicionales

**Goroutines (Implementadas)**:

- Peso: ~2KB por goroutine
- Can create 100K+ goroutines
- Scheduling: Go runtime
- Ideal para: I/O-bound, miles de conexiones

**Threads OS (alternativa)**:

- Peso: ~2MB por thread
- Can create ~1K threads
- Scheduling: Sistema operativo
- Ideal para: CPU-bound

Elegimos Goroutines porque cada cliente WebSocket es I/O-bound (espera a que escriba en el socket).

### 3. Filtro de Malas Palabras: Ubicación

**Ubicación Actual (ReadPump)**:

- Bloqueamos ANTES de Hub
- Antes de Redis
- Shadowban silencioso

**Alternativa (WritePump)**:

- Bloqueamos DESPUÉS de Redis
- Ya publicado en todos los servidores
- Menos eficiente

Elegimos ReadPump porque es más seguro (nunca toca Redis).

### 4. Heartbeat: Ping/Pong

**Problema**: TCP puede no detectar desconexiones unilaterales

- Cliente se "congela" pero socket abierto
- Servidor no sabe que está muerto
- Acumula memoria

**Solución**: Heartbeat cada `pingPeriod`

- Servidor envía Ping
- Cliente responde Pong
- Si no responde en `pongWait`, timeout

## Implementación de Reglas de Seguridad

### R-SEC-05: Inspección de Mensajes en Tiempo Real

**Status Fase 4**: Completamente implementado

```go
// Validación preventiva
if containsBadWords(message) {
    log.Printf("ALERTA: Usuario %s intentó: %s", userID, string(message))
    // Bloquear envío
    continue
}

// Notificación al usuario (silenciosa)
c.Send <- []byte("Mensaje bloqueado por sistema de seguridad")
```

**Características**:

- Case-insensitive detection
- Substring matching
- Shadowban: Usuario no sabe exactamente por qué
- Log para auditoría
- Escalable: Agregar palabras es trivial

### R-SEC-02, R-SEC-03: Sin cambios desde Fase 1

### R-SEC-01: Sin cambios desde Fase 2

## Próximos Pasos (Fase 5 y 6)

### Fase 5: Frontend Flutter

1. Conectar WebSocket desde Flutter
2. Interfaz de chat UI
3. Notificaciones push
4. Upload de fotos perfil

### Fase 6: Producción

1. TLS/SSL para WebSocket (wss://)
2. Rate limiting por usuario
3. Persistencia de chat en BD (opcional)
4. Logging centralizado
5. Monitoring y alertas
6. Kubernetes deployment

## Testing y Evidencia

### Evidencia Proporcionada

**chat_test1.png**:

- Captura de pantalla de chat funcional
- Múltiples mensajes entre usuarios
- Timestamps en tiempo real
- Demuestra: Bidireccionalidad, persistencia de sesión

**bad_word_test1.png**:

- Captura de intento de envío de palabra prohibida
- Mensaje bloqueado por sistema
- Notificación "Mensaje bloqueado"
- Demuestra: R-SEC-05 funcionando

## Stack de Dependencias Completo

| Paquete             | Versión | Propósito                    | Fase Añadido |
| ------------------- | ------- | ---------------------------- | ------------ |
| godotenv            | v1.5.1  | Variables de entorno         | Fase 0       |
| gorm                | v1.31.1 | ORM para BD                  | Fase 0       |
| driver/postgres     | v1.6.0  | Driver GORM PostgreSQL       | Fase 0       |
| pgx                 | v5.6.0  | Driver bajo nivel PostgreSQL | Fase 0       |
| gin                 | v1.11.0 | Framework web                | Fase 1       |
| golang.org/x/crypto | v0.46.0 | Bcrypt                       | Fase 1       |
| jwt/v5              | v5.3.0  | JSON Web Tokens              | Fase 1       |
| google/uuid         | v1.6.0  | Generación de UUIDs          | Fase 2       |
| gorilla/websocket   | v1.5.3  | Protocolo WebSocket          | Fase 4       |
| redis/go-redis      | v9.17.2 | Cliente Redis                | Fase 4       |

## Referencias

- Gorilla WebSocket: https://github.com/gorilla/websocket
- Redis Pub/Sub: https://redis.io/docs/interact/pubsub/
- Go Concurrency Patterns: https://go.dev/blog/pipelines
- WebSocket Protocol: https://tools.ietf.org/html/rfc6455
- Goroutine vs Thread: https://medium.com/@mustafaansal/goroutine-vs-thread-9e2584d96c42
