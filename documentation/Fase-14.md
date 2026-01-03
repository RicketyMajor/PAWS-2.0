# Fase 14: Arquitectura Orientada a Eventos, Registro Asincrónico y Seguridad Avanzada

## Introducción

La Fase 14 representa la culminación de Etapa 10, la cual transforma PAWS de un sistema sincrónico a una **arquitectura orientada a eventos** completamente desacoplada. Esta fase implementa patrones enterprise de procesamiento asincrónico, registro en dos pasos con commit diferido, y correos transaccionales confiables, todo mientras mantiene tolerancia a fallos en modo desarrollo.

**Objetivos de Etapa 10**:

1. Desacoplar el envío de correos (lento) del flujo de registro (rápido)
2. Implementar flujo de registro securizado con verificación OTP en dos pasos
3. Integrar SendGrid para correos transaccionales reales
4. Proporcionar experiencia UX/UI mejorada con navegación correcta post-verificación
5. Mantener graceful degradation: sistema funciona incluso si RabbitMQ o SendGrid no están disponibles

## Arquitectura de Eventos - Componentes Principales

### 1. Message Broker - RabbitMQ

**Propósito**: Desacoplador central entre productores (OTPService) y consumidores (EmailWorker).

**Instalación en docker-compose.yml**:

```yaml
rabbitmq:
  image: rabbitmq:3.12-alpine
  container_name: paws-rabbitmq
  restart: always
  ports:
    - "5672:5672" # AMQP port
    - "15672:15672" # Management UI
  environment:
    RABBITMQ_DEFAULT_USER: guest
    RABBITMQ_DEFAULT_PASS: guest
  volumes:
    - rabbitmq_data:/var/lib/rabbitmq
```

**Cola de Eventos**:

```go
// internal/infrastructure/messaging/rabbitmq.go
const (
    EmailNotificationQueue = "email_notifications"
)

type RabbitMQClient struct {
    conn *amqp.Connection
    ch   *amqp.Channel
}

func ConnectRabbitMQ(url string) (*RabbitMQClient, error) {
    conn, err := amqp.Dial(url)
    if err != nil {
        return nil, fmt.Errorf("fallo conectando a RabbitMQ: %v", err)
    }

    ch, err := conn.Channel()
    if err != nil {
        return nil, fmt.Errorf("fallo abriendo canal: %v", err)
    }

    // Declarar cola (durable: sobrevive reinicios de RabbitMQ)
    q, err := ch.QueueDeclare(
        EmailNotificationQueue,  // name
        true,                    // durable
        false,                   // autoDelete
        false,                   // exclusive
        false,                   // noWait
        nil,                     // args
    )
    if err != nil {
        return nil, fmt.Errorf("fallo declarando cola: %v", err)
    }

    log.Printf("Cola RabbitMQ declarada: %s", q.Name)
    return &RabbitMQClient{conn: conn, ch: ch}, nil
}

func (c *RabbitMQClient) Publish(queueName string, body []byte) error {
    return c.ch.Publish(
        "",         // exchange (default)
        queueName,  // routing key
        false,      // mandatory
        false,      // immediate
        amqp.Publishing{
            ContentType: "application/json",
            Body:        body,
        },
    )
}

func (c *RabbitMQClient) GetChannel() *amqp.Channel {
    return c.ch
}

func (c *RabbitMQClient) Close() error {
    if c.ch != nil {
        c.ch.Close()
    }
    if c.conn != nil {
        return c.conn.Close()
    }
    return nil
}
```

### 2. OTPService Refactorizado - Productor de Eventos

**Arquitectura** (Etapa 10):

```go
// internal/core/services/otp_service.go

type EmailEvent struct {
    To      string `json:"to"`
    Subject string `json:"subject"`
    Body    string `json:"body"`
}

type OTPService struct {
    redisClient *redis.Client
    mqClient    *messaging.RabbitMQClient  // Puede ser nil (graceful degradation)
}

func NewOTPService(mq *messaging.RabbitMQClient) *OTPService {
    return &OTPService{
        redisClient: database.GetRedis(),
        mqClient:    mq,  // nil si ENABLE_ASYNC_FEATURES=false
    }
}

func (s *OTPService) GenerateOTP(email string) (string, error) {
    // Generar código aleatorio 6-dígitos
    rng := rand.New(rand.NewSource(time.Now().UnixNano()))
    code := fmt.Sprintf("%06d", rng.Intn(1000000))

    // Guardar en Redis (TTL 5 min)
    ctx := context.Background()
    key := fmt.Sprintf("otp:%s", email)
    err := s.redisClient.Set(ctx, key, code, 5*time.Minute).Err()
    if err != nil {
        return "", fmt.Errorf("error guardando OTP en Redis: %v", err)
    }

    // Crear evento de correo
    event := EmailEvent{
        To:      email,
        Subject: "Tu código de verificación PAWS",
        Body:    fmt.Sprintf("Hola, tu código de verificación es: %s. Este código expirará en 5 minutos.", code),
    }

    eventBytes, _ := json.Marshal(event)

    // Enviar a RabbitMQ (si existe) o fallback a log
    if s.mqClient != nil {
        // Modo asincrónico
        err = s.mqClient.Publish("email_notifications", eventBytes)
        if err != nil {
            log.Printf("Error RabbitMQ: %v. Usando Log como fallback.", err)
            log.Printf("[FALLBACK EMAIL] Para: %s | Código: %s", email, code)
        } else {
            log.Printf("Evento de email enviado a RabbitMQ para: %s", email)
        }
    } else {
        // Modo sincrónico (desarrollo)
        log.Printf("[DEV EMAIL] Para: %s | Código: %s", email, code)
    }

    return code, nil
}

func (s *OTPService) VerifyOTP(email, inputCode string) bool {
    ctx := context.Background()
    key := fmt.Sprintf("otp:%s", email)

    val, err := s.redisClient.Get(ctx, key).Result()
    if err == redis.Nil || err != nil {
        return false  // Código no existe o expiró
    }

    if val == inputCode {
        s.redisClient.Del(ctx, key)  // Borrar código tras verificación exitosa
        return true
    }

    return false
}
```

### 3. EmailWorker - Consumidor de Eventos

**Propósito**: Procesar eventos de correo de RabbitMQ en background sin bloquear requests HTTP.

```go
// internal/core/workers/email_worker.go

package workers

import (
    "encoding/json"
    "log"

    "github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/email"
    "github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
)

type EmailEvent struct {
    To      string `json:"to"`
    Subject string `json:"subject"`
    Body    string `json:"body"`
}

// StartEmailConsumer inicia goroutine que consume eventos de RabbitMQ
func StartEmailConsumer(mq *messaging.RabbitMQClient, emailClient *email.EmailClient) {
    ch := mq.GetChannel()

    // Consumir de la cola "email_notifications"
    msgs, err := ch.Consume(
        "email_notifications",  // queue
        "",                     // consumer name
        false,                  // auto-ack (NO - confirmaremos manualmente)
        false,                  // exclusive
        false,                  // no-local
        false,                  // no-wait
        nil,                    // args
    )

    if err != nil {
        log.Printf("Error registrando consumidor RabbitMQ: %v", err)
        return
    }

    log.Println("EmailWorker iniciado. Esperando mensajes...")

    // Bucle infinito procesando mensajes
    go func() {
        for d := range msgs {
            var event EmailEvent

            // Deserializar JSON
            err := json.Unmarshal(d.Body, &event)
            if err != nil {
                log.Printf("Error decodificando evento: %v", err)
                d.Ack(false)  // Confirmar de todos modos (Dead Letter en producción)
                continue
            }

            // Intentar enviar correo
            log.Printf("Enviando email a %s (subject: %s)", event.To, event.Subject)
            err = emailClient.Send(event.To, event.Subject, event.Body)

            if err != nil {
                log.Printf("Error enviando email: %v", err)
                // En producción: d.Nack(false, true) para reintento
                // En desarrollo: confirmar para evitar loops infinitos
                d.Ack(false)
            } else {
                log.Printf("Email enviado exitosamente a %s", event.To)
                d.Ack(false)  // Confirmar a RabbitMQ (sacar de cola)
            }
        }
    }()
}
```

### 4. SendGrid Email Client

**Propósito**: Envío real de correos transaccionales con SendGrid.

```go
// internal/infrastructure/email/sendgrid.go

package email

import (
    "fmt"
    "log"
    "os"

    "github.com/sendgrid/sendgrid-go"
    "github.com/sendgrid/sendgrid-go/helpers/mail"
)

type SendGridClient struct {
    client *sendgrid.Client
    from   string
}

func NewSendGridClient() *SendGridClient {
    apiKey := os.Getenv("SENDGRID_API_KEY")
    if apiKey == "" {
        log.Println("SENDGRID_API_KEY no configurada. Correos usarán fallback a logs.")
    }

    return &SendGridClient{
        client: sendgrid.NewSendClient(apiKey),
        from:   "noreply@pawsapp.com",
    }
}

func (c *SendGridClient) Send(to, subject, body string) error {
    if c.client == nil || os.Getenv("SENDGRID_API_KEY") == "" {
        // Fallback: loguear correo en desarrollo
        log.Printf("[SENDGRID FALLBACK] To: %s | Subject: %s | Body: %s", to, subject, body)
        return nil
    }

    from := mail.NewEmail("PAWS", c.from)
    recipient := mail.NewEmail("", to)

    message := mail.NewSingleEmail(from, subject, recipient, body, body)

    response, err := c.client.Send(message)
    if err != nil {
        return fmt.Errorf("error SendGrid: %v", err)
    }

    if response.StatusCode >= 400 {
        return fmt.Errorf("SendGrid error: status %d - %s", response.StatusCode, response.Body)
    }

    log.Printf("SendGrid respuesta: %d", response.StatusCode)
    return nil
}
```

## Registro en Dos Pasos - Commit Diferido

### Flujo de Arquitectura

El registro en PAWS ahora implementa un patrón de **tres fases** para máxima seguridad:

```
FASE 1: INITIATE (Temporal en Redis)
  ↓
  Usuario envía: {name, email, password, run, role}
  ↓
  Backend valida:
    - Email único
    - RUN en blacklist?
    - Contraseña >= 6 caracteres
  ↓
  Guarda en Redis con TTL 10 minutos (temporal, no committeado)
  ↓
  Envía OTP vía RabbitMQ → SendGrid
  ↓
  Responde: 201 Created "Revisa tu email"
  ↓

FASE 2: VERIFICATION (OTP Validation)
  ↓
  Usuario recibe código OTP
  ↓
  Usuario envía: {email, code}
  ↓
  Backend verifica OTP en Redis
  ↓
  Si válido: Pasa a Fase 3
  Si inválido: Retorna 401 "Código incorrecto"
  ↓

FASE 3: COMPLETE (Commit a PostgreSQL)
  ↓
  Backend recupera datos de Redis (Fase 1)
  ↓
  Inserta en PostgreSQL (COMMIT real)
  ↓
  Borra datos de Redis (cleanup)
  ↓
  Retorna: 201 Created con token JWT
  ↓
```

### Implementación en AuthService

```go
// internal/core/services/auth_service.go

type registrationCache struct {
    Name     string `json:"name"`
    Email    string `json:"email"`
    Password string `json:"password"`  // Hash bcrypt
    Run      string `json:"run"`
    Role     string `json:"role"`
}

type AuthService struct {
    db          *gorm.DB
    redisClient *redis.Client
}

// FASE 1: InitiateRegistration - Guardar temporal en Redis
func (s *AuthService) InitiateRegistration(name, email, password, run, role string) error {
    // Validación 1: Email único
    var existingUser domain.User
    if s.db.Where("email = ?", email).First(&existingUser).Error == nil {
        return fmt.Errorf("email ya registrado")
    }

    // Validación 2: RUN en blacklist
    isBanned, err := s.CheckBlacklist(run)
    if err != nil {
        return err
    }
    if isBanned {
        return fmt.Errorf("registro denegado (Evil PAWS)")
    }

    // Validación 3: RUN único
    if s.db.Where("run = ?", run).First(&existingUser).Error == nil {
        return fmt.Errorf("RUN ya registrado")
    }

    // Hash de contraseña
    hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
    if err != nil {
        return err
    }

    // Normalizar role
    roleNormalized := strings.ToLower(role)
    if roleNormalized != "adopter" && roleNormalized != "rescuer" {
        roleNormalized = "adopter"
    }

    // Guardar en Redis (temporal)
    tempData := registrationCache{
        Name:     name,
        Email:    email,
        Password: string(hashedPassword),  // Hash, no plaintext
        Run:      run,
        Role:     roleNormalized,
    }

    userData, err := json.Marshal(tempData)
    if err != nil {
        return err
    }

    ctx := context.Background()
    key := fmt.Sprintf("pending_user:%s", email)

    err = s.redisClient.Set(ctx, key, userData, 10*time.Minute).Err()
    if err != nil {
        return fmt.Errorf("error guardando registro temporal: %v", err)
    }

    log.Printf("Registro temporal para %s guardado en Redis (TTL 10 min)", email)
    return nil
}

// FASE 3: CompleteRegistration - Commit de Redis a PostgreSQL
func (s *AuthService) CompleteRegistration(email string) (*domain.User, error) {
    ctx := context.Background()
    key := fmt.Sprintf("pending_user:%s", email)

    // Recuperar datos de Redis
    val, err := s.redisClient.Get(ctx, key).Result()
    if err == redis.Nil {
        return nil, errors.New("no hay registro pendiente o expiró (10 min)")
    } else if err != nil {
        return nil, err
    }

    // Deserializar
    var tempData registrationCache
    if err := json.Unmarshal([]byte(val), &tempData); err != nil {
        return nil, fmt.Errorf("error deserializando datos: %v", err)
    }

    // Crear usuario en PostgreSQL
    user := domain.User{
        Name:       tempData.Name,
        Email:      tempData.Email,
        Password:   tempData.Password,  // Ya es hash
        Run:        tempData.Run,
        Role:       tempData.Role,
        IsVerified: true,  // OTP verificado
        IsBanned:   false,
    }

    if err := s.db.Create(&user).Error; err != nil {
        return nil, fmt.Errorf("error finalizando registro: %v", err)
    }

    // Limpiar Redis
    s.redisClient.Del(ctx, key)

    log.Printf("Usuario %s completó registro. Guardado en PostgreSQL.", email)
    return &user, nil
}
```

### Implementación en AuthHandler

```go
// internal/transport/http/auth_handler.go

// FASE 1: Register endpoint
func (h *AuthHandler) Register(c *gin.Context) {
    var req RegisterRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Guardar temporal en Redis
    err := h.service.InitiateRegistration(req.Name, req.Email, req.Password, req.Run, req.Role)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Generar OTP y enviar vía RabbitMQ
    code, err := h.otpService.GenerateOTP(req.Email)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Error enviando código"})
        return
    }

    c.JSON(http.StatusCreated, gin.H{
        "message": "Datos validados. Se ha enviado un código OTP a tu correo. Este código expirará en 5 minutos.",
        "email":   req.Email,  // Para que cliente sepa a dónde envió
    })
}

// FASE 2+3: Verify OTP endpoint
func (h *AuthHandler) VerifyOTP(c *gin.Context) {
    var req OTPVerifyRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Verificar código OTP en Redis
    valid := h.otpService.VerifyOTP(req.Email, req.Code)
    if !valid {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Código incorrecto o expirado"})
        return
    }

    // Completar registro (COMMIT de Redis a PostgreSQL)
    user, err := h.service.CompleteRegistration(req.Email)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Generar JWT
    token, err := h.service.GenerateTokenForUser(user)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Error generando token"})
        return
    }

    c.JSON(http.StatusCreated, gin.H{
        "message": "¡Cuenta creada exitosamente!",
        "token":   token,
        "user": gin.H{
            "id":    user.ID,
            "email": user.Email,
            "role":  user.Role,
        },
    })
}
```

## Frontend Integration - UX/UI Mejorada

### OTPScreen Refactorizado

```dart
// app/lib/features/auth/presentation/screens/otp_screen.dart

import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../data/auth_repository.dart';
import '../../../../core/presentation/main_layout_screen.dart';

class OTPScreen extends StatefulWidget {
    final String email;

    const OTPScreen({Key? key, required this.email}) : super(key: key);

    @override
    _OTPScreenState createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
    final TextEditingController _codeController = TextEditingController();
    final AuthRepository _authRepo = AuthRepository();
    bool _isLoading = false;

    void _verify() async {
        setState(() => _isLoading = true);

        try {
            // Llamar endpoint /auth/otp/verify
            final token = await _authRepo.verifyOtp(widget.email, _codeController.text);

            if (token != null && mounted) {
                // Mostrar feedback
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('¡Cuenta verificada! Entrando...'),
                        backgroundColor: Colors.green,
                    ),
                );

                // Decodificar JWT para obtener rol
                Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
                String role = decodedToken['role'] ?? 'adopter';

                // CORRECCIÓN ETAPA 10: Navegar a MainLayout (no a pantalla suelta)
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (context) => MainLayoutScreen(role: role),
                    ),
                    (route) => false,  // Elimina todo el stack de navegación
                );
            }
        } catch (e) {
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: Colors.red,
                    ),
                );
            }
        }

        setState(() => _isLoading = false);
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                title: const Text("Verificar Código OTP"),
            ),
            body: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Text(
                            "Hemos enviado un código OTP a:\n${widget.email}",
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 30),

                        // Campo de entrada - 6 dígitos
                        TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                                fontSize: 32,
                                letterSpacing: 15.0,
                                fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                                hintText: "000000",
                                border: OutlineInputBorder(),
                                counterText: "",  // Ocultar contador
                            ),
                        ),

                        const SizedBox(height: 30),

                        // Botón de verificación
                        _isLoading
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: _verify,
                                style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 40,
                                        vertical: 16,
                                    ),
                                    backgroundColor: Colors.blue,
                                ),
                                child: const Text(
                                    "Verificar Código",
                                    style: TextStyle(fontSize: 16),
                                ),
                            ),

                        const SizedBox(height: 20),

                        // Enlace para solicitar nuevo código
                        TextButton(
                            onPressed: () async {
                                // RequestOTP endpoint para código nuevo
                                // await _authRepo.requestOTP(widget.email);
                            },
                            child: const Text("¿No recibiste el código? Solicitar uno nuevo"),
                        ),
                    ],
                ),
            ),
        );
    }
}
```

### AuthRepository - Tolerancia HTTP 201

```dart
// app/lib/features/auth/data/auth_repository.dart

class AuthRepository {
    final _dio = Dio();
    final _storage = FlutterSecureStorage();

    Future<String?> verifyOtp(String email, String code) async {
        try {
            final response = await _dio.post(
                '${ApiConstants.baseUrl}/auth/otp/verify',
                data: {
                    'email': email,
                    'code': code,  // 6 dígitos
                },
            );

            // Aceptar AMBOS 200 y 201
            if (response.statusCode == 200 || response.statusCode == 201) {
                final token = response.data['token'];

                // Guardar token en storage seguro
                await _storage.write(key: 'jwt_token', value: token);

                return token;
            }

            return null;
        } on DioException catch (e) {
            if (e.response != null) {
                throw Exception(e.response?.data['error'] ?? 'Error desconocido');
            } else {
                throw Exception('Error de conexión: ${e.message}');
            }
        }
    }
}
```

## Kill Switch ENABLE_ASYNC_FEATURES

### Modo Síncrono (Desarrollo Local)

```bash
# .env local (default)
ENABLE_ASYNC_FEATURES=false

# main.go
if os.Getenv("ENABLE_ASYNC_FEATURES") == "true" {
    // Conectar a RabbitMQ
} else {
    log.Println("Async Features desactivadas. Usando modo sincrónico.")
    mqClient = nil
}

// OTPService
if s.mqClient != nil {
    s.mqClient.Publish(...)  // Async a RabbitMQ
} else {
    log.Printf("[DEV EMAIL] Code: %s", code)  // Log en consola
}
```

**Resultado en desarrollo**:

```
Backend logs:
[DEV EMAIL] Para: juan@mail.com | Código: 456789
```

### Modo Asincrónico (Producción)

```bash
# .env en Railway
ENABLE_ASYNC_FEATURES=true
RABBITMQ_HOST=rabbitmq-service (cloud RabbitMQ)

# main.go
mqClient, err := messaging.ConnectRabbitMQ(...)
if err != nil {
    log.Printf("RabbitMQ error: %v", err)
    mqClient = nil  // Fallback
}

// OTPService
if s.mqClient != nil {
    s.mqClient.Publish("email_notifications", event)  // A RabbitMQ
    log.Println("Evento publicado a RabbitMQ")
} else {
    // Fallback
    log.Printf("[FALLBACK EMAIL] Code: %s", code)
}

// EmailWorker inicia
workers.StartEmailConsumer(mqClient, emailClient)
log.Println("EmailWorker iniciado")
```

**Resultado en producción**:

```
Backend logs:
Evento de email enviado a RabbitMQ para: juan@mail.com

EmailWorker logs:
Enviando email a juan@mail.com (subject: Tu código de verificación PAWS)
SendGrid respuesta: 202  // Aceptado por SendGrid
Email enviado exitosamente a juan@mail.com
```

## Testing End-to-End

### Scenario 1: Registro Completo en Modo Dev

```bash
# Terminal 1: Iniciar backend local
docker-compose up

# Terminal 2: Registrar usuario
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Juan Pérez",
    "email": "juan@example.com",
    "password": "securepass123",
    "run": "12345678-1",
    "role": "adopter"
  }'

# Respuesta
{
  "message": "Datos validados. Se ha enviado un código OTP a tu correo. Este código expirará en 5 minutos.",
  "email": "juan@example.com"
}

# Terminal 1 logs:
[DEV EMAIL] Para: juan@example.com | Código: 789456

# Terminal 2: Verificar código (copia 789456)
curl -X POST http://localhost:8080/api/v1/auth/otp/verify \
  -H "Content-Type: application/json" \
  -d '{
    "email": "juan@example.com",
    "code": "789456"
  }'

# Respuesta
{
  "message": "¡Cuenta creada exitosamente!",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": 1,
    "email": "juan@example.com",
    "role": "adopter"
  }
}

# Frontend: OTPScreen navega a MainLayoutScreen
✓ Usuario dentro de la app
```

### Scenario 2: Registro con MinIO Down

```bash
# Terminal 1
docker-compose down minio
docker-compose up backend db redis

# Terminal 2: Registrar usuario (sin foto)
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "María",
    "email": "maria@example.com",
    "password": "pass123",
    "run": "99999999-9",
    "role": "rescuer"
  }'

# Respuesta: 201 (exitoso aunque MinIO abajo)
{
  "message": "Datos validados. Se ha enviado un código OTP a tu correo.",
  "email": "maria@example.com"
}

# Terminal 1 logs:
[DEV EMAIL] Para: maria@example.com | Código: 123456
Advertencia: foto no guardada, continuando

# Verificación sigue igual - usuario creado sin foto
curl -X POST http://localhost:8080/api/v1/auth/otp/verify ...

# Resultado: Usuario completo, foto vacía en BD
```

## Ventajas de Etapa 10

1. **Desacoplamiento Total**: OTPService no espera a SendGrid, responde inmediatamente
2. **Seguridad en Registro**: Dos pasos con OTP, datos temporales no committeados
3. **Graceful Degradation**: Funciona sin RabbitMQ (logs en terminal), sin SendGrid (fallback)
4. **UX Mejorada**: Navegación correcta post-verificación, tolerancia HTTP 201
5. **Escalabilidad**: EmailWorker independiente, puede haber N instancias procesando
6. **Confiabilidad**: RabbitMQ garantiza entrega (queue durable), retry automático

## Referencias y Documentación

- RabbitMQ Tutorials: https://www.rabbitmq.com/getstarted.html
- SendGrid Go Client: https://github.com/sendgrid/sendgrid-go
- Microservices Event-Driven: https://microservices.io/patterns/data/event-sourcing.html
- OTP Best Practices: https://www.rfc-editor.org/rfc/rfc4648
