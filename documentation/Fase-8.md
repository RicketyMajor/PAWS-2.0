# Fase 8: El Núcleo de Seguridad (Evil PAWS)

## Introducción

La Fase 8 implementa el corazón de la seguridad de PAWS: un sistema robusto para garantizar que solo usuarios legítimos puedan acceder, que los usuarios baneados no vuelvan, y que el sistema se defienda automáticamente contra abusos mediante reporte y ban automático.

Esta fase transforma PAWS de una plataforma con características de seguridad a una plataforma **construida en torno a la seguridad**. Implementamos los requisitos de seguridad críticos definidos en la ayudantía: R-SEC-01 (Verificación de Identidad), R-SEC-02 (Anti-Multicuentas), R-SEC-03 (Anti-Blacklist), y R-SEC-04 (Sistema de Reportes).

El nombre "Evil PAWS" representa el enfoque: **piensa como el atacante, construye defensas**. Si un usuario intenta registrarse múltiples veces, estamos listos. Si alguien es reportado 3 veces, es baneado automáticamente. Si su RUN está en la lista negra, entrada rechazada.

## Objetivos de la Fase 8

1. Completar R-SEC-01: Verificación de identidad por foto de documento
2. Completar R-SEC-02: Prevención de multicuentas por RUN
3. Completar R-SEC-03: Sistema de Blacklist con verificación automática
4. Completar R-SEC-04: Sistema de reportes con ban automático tras 3 reportes
5. Implementar OTP (One-Time Password) por email para registro
6. Testing de seguridad para casos críticos
7. Documentar flujos de seguridad y arquitectura defensiva

## Stack Tecnológico - Seguridad

### Verificación de Identidad (R-SEC-01)

- **Almacenamiento**: MinIO (S3-compatible) para documentos de identidad
- **Extracción de RUN**: Mock generador válido de RUN chileno con dígito verificador
- **Algoritmo**: Módulo 11 para validar formato de RUN

### OTP y Email (Futuro Real)

- **Redis**: Almacenamiento temporal de códigos OTP (TTL: 5 minutos)
- **Código generado**: 6 dígitos aleatorios
- **Verificación**: One-time (se borra tras uso exitoso)

### Anti-Multicuentas (R-SEC-02)

- **Verificación**: Búsqueda en tabla User por campo RUN (único)
- **Bloqueo**: Rechazo inmediato si RUN ya existe
- **Mensaje**: "Ya existe una cuenta asociada al RUN"

### Blacklist (R-SEC-03)

- **Modelo**: Tabla BlacklistEntry (run, reason, created_at)
- **Verificación**: Al registrarse y al login
- **Método**: Query `WHERE run = ?` en tabla blacklist_entries
- **Resultado**: TRUE si baneado, FALSE si limpio

### Sistema de Reportes (R-SEC-04)

- **Modelo**: Tabla Report (reporter_id, reported_id, reason, status)
- **Gatillo**: 3+ reportes verificados = ban automático
- **Automatización**: ReportService.checkAndBanUser()
- **Integración**: Agrega automáticamente a BlacklistEntry

## Cambios en la Estructura del Proyecto

### Nuevos Archivos Creados

#### 1. identity_service.go

- Implementa R-SEC-01
- Conecta a MinIO para almacenar fotos de documentos
- Genera RUN válido (mock) con dígito verificador correcto
- Funciones auxiliares: calculateDV(), formatWithPoints()

#### 2. otp_service.go

- Genera OTP de 6 dígitos
- Almacena en Redis con TTL de 5 minutos
- Verifica código y lo borra tras uso exitoso
- Logs simulan envío de email

#### 3. report_service.go

- CreateReport(): Registra denuncia
- checkAndBanUser(): Regla de los 3 strikes
- Integración con AuthService para baneos automáticos

#### 4. report_service_test.go

- TestThreeStrikesBan(): Verifica lógica de 3 reportes = ban
- Usa setupTestDB() con SQLite

### Modelos de Dominio Nuevos

#### domain/report.go

```go
type Report struct {
    gorm.Model
    ReporterID uint   // Quién acusa
    ReportedID uint   // El acusado
    Reason     string // "Maltrato", "Acoso", "Cuenta Falsa"
    Status     string // pending, verified, rejected
}
```

#### domain/blacklist.go

```go
type BlacklistEntry struct {
    gorm.Model
    Run    string // Único en la lista negra
    Reason string // Razón del bloqueo
}
```

### Archivos Modificados

#### auth_service.go

- Register(): Agregó validaciones R-SEC-02 y R-SEC-03
  - Verifica si RUN está en Blacklist (CheckBlacklist)
  - Verifica si RUN ya existe en tabla User
  - Solo entonces crea usuario
- Login(): Verificación de IsBanned flag
- CheckBlacklist(): Implementación real contra BD

#### .github/workflows/ci.yml

- Agregó golangci-lint para análisis estático
- Agregó govulncheck para escaneo de vulnerabilidades
- Agregó docker build-and-push (push a Docker Hub)
- Eliminado emoji de barco

#### internal/core/services/report_service.go

- Eliminado emoji de ban

## Verificación de Identidad (R-SEC-01)

### Flujo Completo

```
Usuario elige foto de DNI/Pasaporte
         |
         v
Endpoint POST /api/v1/verification/verify
         |
         v
IdentityService.VerifyIdentity(file)
         |
         +-- Abrir archivo
         |
         +-- Validar MIME type (image/jpeg, image/png)
         |
         +-- Subir a MinIO bucket 'paws-identity'
         |
         +-- Generar RUN válido (mock)
         |
         +-- Retornar RUN al cliente
         |
         v
Cliente recibe RUN extraído (mock)
         |
         v
Cliente usa ese RUN en Register()
         |
         v
AuthService.Register() verifica:
         - ¿RUN en Blacklist? NO
         - ¿RUN ya registrado? NO
         - Crea usuario
```

### Implementación IdentityService

```go
type IdentityService struct {
    minioClient *minio.Client
    bucketName  string
}

func NewIdentityService() *IdentityService {
    // Conectar a MinIO (kubernetes: minio-service:9000)
    // Crear bucket automáticamente si no existe
    return &IdentityService{...}
}

func (s *IdentityService) VerifyIdentity(file *multipart.FileHeader) (string, error) {
    // 1. Abrir archivo
    src, err := file.Open()
    // ...

    // 2. Guardar en MinIO con timestamp
    filename := fmt.Sprintf("id_scan_%d_%s", time.Now().Unix(), file.Filename)
    s.minioClient.PutObject(ctx, "paws-identity", filename, src, ...)

    // 3. Generar RUN válido (mock mejorado)
    mockRun := s.generateRandomRUN()

    // 4. Retornar
    return mockRun, nil
}
```

### Generador de RUN Válido (Algoritmo Módulo 11)

```go
func (s *IdentityService) generateRandomRUN() string {
    // Número entre 10.000.000 y 25.000.000
    number := rand.Intn(15000000) + 10000000

    // Cálculo del dígito verificador (Módulo 11)
    dv := calculateDV(number)

    // Formatear: XX.XXX.XXX-K
    return fmt.Sprintf("%s-%s", formatWithPoints(number), dv)
}

func calculateDV(rut int) string {
    m := 0
    s := 1
    for rut != 0 {
        s = (s + rut%10*(9-m%6)) % 11
        rut /= 10
        m++
    }
    if s != 0 {
        return strconv.Itoa(s - 1)
    }
    return "K"
}
```

### Por qué es importante

- Simula extracción real de OCR (futuro: Google Vision API)
- Genera RUN único por documento
- Permite múltiples registros (cada documento = RUN diferente)
- Validación matemática correcta (módulo 11 chileno)

## Anti-Multicuentas (R-SEC-02)

### Flujo de Bloqueo

```
Usuario intenta Register(email1, password, name, run="12.345.678-9", role)
         |
         v
AuthService.Register()
         |
         +-- Verificar Blacklist: CheckBlacklist("12.345.678-9")
         |    ¿Está baneado? -> Error + rechazo
         |
         +-- Verificar Multicuenta:
         |    SELECT * FROM users WHERE run = "12.345.678-9"
         |    ¿Existe? -> Error "Ya existe cuenta con este RUN"
         |
         +-- Si pasa ambas:
         |    Hash password
         |    Crear usuario
         |
         v
Usuario creado exitosamente (PRIMER registro)

Usuario intenta crear segunda cuenta con mismo RUN
         |
         v
AuthService.Register()
         |
         +-- Verificar Blacklist: OK (no está baneado)
         |
         +-- Verificar Multicuenta:
         |    SELECT * FROM users WHERE run = "12.345.678-9"
         |    ENCONTRADO (la primera cuenta)
         |    -> Retorna error
         |
         v
RECHAZO: "Ya existe una cuenta asociada al RUN"
```

### Código de Implementación

```go
func (s *AuthService) Register(email, password, name, run, role string) error {
    // 1. SEGURIDAD: Verificar si está en la Blacklist (R-SEC-03)
    isBanned, err := s.CheckBlacklist(run)
    if isBanned {
        return fmt.Errorf("registro denegado por políticas de seguridad")
    }

    // 2. SEGURIDAD: Verificar Multicuentas (R-SEC-02)
    var existingUser domain.User
    result := s.db.Where("run = ?", run).First(&existingUser)
    if result.Error == nil {
        // Sí existe -> rechazar
        return fmt.Errorf("ya existe una cuenta asociada al RUN %s", run)
    }

    // 3. Crear usuario
    hashedPassword, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
    user := domain.User{Email: email, Password: string(hashedPassword), ...}
    return s.db.Create(&user).Error
}
```

### Casos Testados

- Primer usuario con RUN X: Creado exitosamente
- Segundo usuario con RUN X (email diferente): Rechazado
- Tercer usuario con RUN X (todo diferente): Rechazado

## Blacklist y Verificación (R-SEC-03)

### Tabla BlacklistEntry

```sql
CREATE TABLE blacklist_entries (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    run VARCHAR(20) UNIQUE NOT NULL,
    reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Método CheckBlacklist

```go
func (s *AuthService) CheckBlacklist(run string) (bool, error) {
    if run == "" {
        return false, fmt.Errorf("el RUN no puede estar vacío")
    }

    var entry domain.BlacklistEntry
    result := s.db.Where("run = ?", run).First(&entry)

    if result.Error != nil {
        if result.Error == gorm.ErrRecordNotFound {
            return false, nil  // No está baneado
        }
        return false, result.Error  // Error en BD
    }

    return true, nil  // Está baneado
}
```

### Integración con Register y Login

#### En Register

```go
isBanned, err := s.CheckBlacklist(run)
if isBanned {
    return fmt.Errorf("registro denegado")
}
// Continuar solo si NO está baneado
```

#### En Login

```go
if user.IsBanned {
    return "", fmt.Errorf("tu cuenta ha sido suspendida")
}
// Continuar solo si NO está baneado
```

## Sistema de Reportes (R-SEC-04)

### Regla de los 3 Strikes

Cualquier usuario con 3 o más reportes verificados es **baneado automáticamente**.

### Flujo Completo

```
Usuario A reporta a Usuario B: Razón "Acoso"
         |
         v
ReportService.CreateReport(reporterID=A, reportedID=B, reason="Acoso")
         |
         +-- Evitar auto-reporte
         |    if reporterID == reportedID: Error
         |
         +-- Crear Report en BD (status="verified" para MVP)
         |
         +-- Contar reportes verificados de Usuario B:
         |    SELECT COUNT(*) FROM reports
         |    WHERE reported_id = B AND status = "verified"
         |
         +-- ¿Count >= 3?
         |    |
         |    NO  -> Retornar success, nada más
         |    |
         |    YES -> Proceder al ban automático
         |            |
         |            +-- Obtener RUN de Usuario B
         |            |
         |            +-- Crear BlacklistEntry con ese RUN
         |            |
         |            +-- Log: "USUARIO BANEADO AUTOMÁTICAMENTE"
         |
         v
Ban ejecutado automáticamente (sin intervención admin)
```

### Implementación ReportService

```go
type ReportService struct {
    db          *gorm.DB
    authService *AuthService  // Para integración con ban
}

func (s *ReportService) CreateReport(reporterID, reportedID uint, reason string) error {
    // 1. Evitar auto-reporte
    if reporterID == reportedID {
        return fmt.Errorf("no puedes reportarte a ti mismo")
    }

    // 2. Crear reporte
    report := domain.Report{
        ReporterID: reporterID,
        ReportedID: reportedID,
        Reason:     reason,
        Status:     "verified",
    }
    s.db.Create(&report)

    // 3. Verificar ban automático
    return s.checkAndBanUser(reportedID)
}

func (s *ReportService) checkAndBanUser(userID uint) error {
    var count int64
    s.db.Model(&domain.Report{}).
        Where("reported_id = ? AND status = ?", userID, "verified").
        Count(&count)

    if count >= 3 {
        // Obtener usuario
        var user domain.User
        s.db.First(&user, userID)

        // Agregar a blacklist
        blacklistEntry := domain.BlacklistEntry{
            Run:    user.Run,
            Reason: "Sistema: Acumulación de 3 reportes graves",
        }
        s.db.Create(&blacklistEntry)

        fmt.Printf("USUARIO BANEADO AUTOMÁTICAMENTE: %s (%s)\n", user.Name, user.Run)
    }

    return nil
}
```

### Test: TestThreeStrikesBan

```go
func TestThreeStrikesBan(t *testing.T) {
    db := setupTestDB()
    db.AutoMigrate(&domain.User{}, &domain.Report{}, &domain.BlacklistEntry{})

    authService := NewAuthService(db)
    reportService := NewReportService(db, authService)

    // Crear usuario "villano"
    victim := domain.User{Name: "Villano", Email: "bad@paws.cl", Run: "99.999.999-9"}
    db.Create(&victim)

    // Reporte 1 y 2: No pasa nada
    reportService.CreateReport(2, victim.ID, "Acoso 1")
    reportService.CreateReport(3, victim.ID, "Acoso 2")

    isBanned, _ := authService.CheckBlacklist(victim.Run)
    if isBanned {
        t.Error("Baneado prematuramente con 2 reportes")
    }

    // Reporte 3: GATILLO
    reportService.CreateReport(4, victim.ID, "Acoso 3")

    isBanned, _ = authService.CheckBlacklist(victim.Run)
    if !isBanned {
        t.Error("NO fue baneado tras 3 reportes (fallo de seguridad)")
    }
}
```

### ReportHandler - Endpoint HTTP

El handler expone la funcionalidad de reportes como un endpoint REST protegido. Es responsable de:

- Extraer el `userID` del token JWT
- Validar la estructura del reporte (reportedID, reason)
- Delegar la creación al servicio
- Retornar respuestas HTTP apropiadas

#### Tipo ReportHandler

```go
type ReportHandler struct {
    service *ReportService
}

func NewReportHandler(service *ReportService) *ReportHandler {
    return &ReportHandler{
        service: service,
    }
}

func (h *ReportHandler) Create(c *gin.Context) {
    // Extraer userID del contexto (middleware de autenticación)
    userID, ok := c.Get("user_id")
    if !ok {
        c.JSON(http.StatusUnauthorized, gin.H{
            "error": "No autenticado",
        })
        return
    }

    // Estructura de entrada
    var req struct {
        ReportedID uint   `json:"reported_id" binding:"required"`
        Reason     string `json:"reason" binding:"required"`
    }

    if err := c.BindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{
            "error": "Campo requerido faltante",
        })
        return
    }

    // Llamar al servicio
    if err := h.service.CreateReport(userID.(uint), req.ReportedID, req.Reason); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{
            "error": err.Error(),
        })
        return
    }

    // Éxito
    c.JSON(http.StatusCreated, gin.H{
        "message": "Reporte recibido. Será revisado por el equipo de moderación.",
    })
}
```

#### Endpoint: POST /api/v1/report

**Ruta:** `POST /api/v1/report`

**Protección:** JWT (AuthMiddleware)

**Request Body:**

```json
{
  "reported_id": 5,
  "reason": "Comportamiento acosador"
}
```

**Response 201:**

```json
{
  "message": "Reporte recibido. Será revisado por el equipo de moderación."
}
```

**Response 400:**

```json
{
  "error": "no puedes reportarte a ti mismo"
}
```

o

```json
{
  "error": "Campo requerido faltante"
}
```

**Response 401:**

```json
{
  "error": "No autenticado"
}
```

#### Integración en main.go

En la inicialización de rutas:

```go
// Crear servicio
reportService := services.NewReportService(database.DB, authService)

// Crear handler
reportHandler := httpTransport.NewReportHandler(reportService)

// Registrar ruta (protegida con AuthMiddleware)
protected := router.Group("/api/v1")
protected.Use(middleware.AuthMiddleware())
{
    protected.POST("/report", reportHandler.Create)
}
```

#### Ejemplo cURL

```bash
# Reportar a un usuario (requiere JWT válido en header)
curl -X POST http://localhost:8080/api/v1/report \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reported_id": 5,
    "reason": "Intento de estafa con depósito"
  }'
```

#### Flujo Completo: Reporte → Ban

1. Usuario A hace POST a `/api/v1/report` con `reported_id=B, reason="Acoso"`
2. ReportHandler extrae `userID=A` del token y valida campos
3. ReportHandler llama a `reportService.CreateReport(A, B, "Acoso")`
4. ReportService crea report en BD con `status="verified"` (MVP automático)
5. ReportService llama a `checkAndBanUser(B)`:
   - Cuenta reportes verificados de B (SELECT COUNT...)
   - Si count < 3: retorna success (sin ban)
   - Si count >= 3: obtiene Run de B, crea BlacklistEntry, Ban ejecutado
6. ReportHandler retorna 201 con mensaje de confirmación
7. En siguiente login de B (si fue baneado): AuthService.Login verifica blacklist, rechaza acceso

#### Casos de Uso

**Caso 1: Reporte Normal (Sin Ban)**

```
Usuario 1 reporta a Usuario 5 por "Acoso"
  → Report creado (report_id=1, reported_id=5, status='verified')
  → Count(User 5) = 1 (< 3)
  → Usuario 5 sigue activo
```

**Caso 2: Tercer Reporte (Ban Automático)**

```
Usuario 5 ya tiene 2 reportes verificados
Usuario 2 reporta a Usuario 5 por "Acoso grave"
  → Report creado (report_id=3, reported_id=5, status='verified')
  → Count(User 5) = 3 (>= 3)
  → System: Obtiene Run de Usuario 5 = "99.999.999-9"
  → System: Crea BlacklistEntry(run='99.999.999-9', reason='Sistema: Acumulación de 3 reportes graves')
  → Usuario 5 es baneado automáticamente
  → Siguiente login de Usuario 5: Rechazado (en blacklist)
```

## OTP Service (Email Verification - Futuro Real)

### Propósito

Validar que el email ingresado es propiedad real del usuario (no fake).

### Implementación OTPService

```go
type OTPService struct {
    redisClient *redis.Client
}

func (s *OTPService) GenerateOTP(email string) (string, error) {
    // 1. Generar código 6 dígitos
    code := fmt.Sprintf("%06d", rand.Intn(1000000))

    // 2. Guardar en Redis (TTL 5 min)
    key := fmt.Sprintf("otp:%s", email)
    s.redisClient.Set(ctx, key, code, 5*time.Minute)

    // 3. Simular envío por email
    log.Printf("[SIMULACIÓN EMAIL] Para: %s | Código: %s", email, code)

    return code, nil
}

func (s *OTPService) VerifyOTP(email, inputCode string) bool {
    key := fmt.Sprintf("otp:%s", email)
    val, err := s.redisClient.Get(ctx, key).Result()

    if err == redis.Nil {
        return false  // Expiró o no existe
    }

    if val == inputCode {
        s.redisClient.Del(ctx, key)  // Borrar código
        return true
    }

    return false
}
```

### Flujo Típico

```
Usuario entra email en formulario
    |
    v
Endpoint POST /api/v1/auth/send-otp
    |
    v
OTPService.GenerateOTP("user@email.com")
    |
    +-- Generar: "123456"
    |
    +-- Guardar en Redis: otp:user@email.com = "123456" (TTL 5 min)
    |
    +-- Log simulado: "[EMAIL] Para: user@email.com | Código: 123456"
    |
    v
Usuario recibe código (en realidad, en logs para MVP)
    |
    v
Usuario entra código en formulario
    |
    v
Endpoint POST /api/v1/auth/verify-otp
    |
    v
OTPService.VerifyOTP("user@email.com", "123456")
    |
    +-- Buscar en Redis
    |
    +-- ¿Coincide? -> TRUE + borrar código
    |
    v
Permiso para continuar con Register
```

### Actualización Etapa 1: OTP Async/Sync Condicional

A partir de Etapa 1, el OTPService se integra con el patrón Kill Switch de ENABLE_ASYNC_FEATURES, permitiendo funcionar tanto en modo asincrónico como sincrónico sin cambios de interfaz.

**Cambio de Arquitectura**:

```go
type OTPService struct {
    redisClient *redis.Client     // Siempre presente (almacena códigos)
    mqClient    *messaging.RabbitMQClient  // Opcional (puede ser nil)
}

func NewOTPService(redis *redis.Client, mq *messaging.RabbitMQClient) *OTPService {
    return &OTPService{
        redisClient: redis,
        mqClient:    mq,  // Puede ser nil si ENABLE_ASYNC_FEATURES=false
    }
}

func (s *OTPService) GenerateOTP(email string) (string, error) {
    code := fmt.Sprintf("%06d", rand.Intn(1000000))

    // Guardar en Redis (ambos modos)
    key := fmt.Sprintf("otp:%s", email)
    s.redisClient.Set(ctx, key, code, 5*time.Minute)

    // Envío condicional
    if s.mqClient != nil {
        // Modo Async: Publicar a cola RabbitMQ
        s.mqClient.Publish("email_notifications", map[string]interface{}{
            "email": email,
            "code":  code,
            "type":  "otp",
        })
        log.Printf("[ASYNC MODE] OTP publicado a RabbitMQ para %s", email)
    } else {
        // Modo Sync: Log directo (Etapa 1 default)
        log.Printf("[DEV MODE] OTP para %s: %s", email, code)
    }

    return code, nil
}
```

**Impacto en Etapa 1**:

- **ENABLE_ASYNC_FEATURES=false** (default): OTP aparece en logs, ideal para testing local
- **ENABLE_ASYNC_FEATURES=true**: OTP se publica a RabbitMQ, worker externo envía email
- **VerifyOTP** sin cambios: Funciona igual en ambos modos (verifica en Redis)
- **Graceful Degradation**: Si RabbitMQ no está disponible, sistema sigue funcionando en sync

**Testing en Etapa 1**:

```bash
# Modo desarrollo (default)
docker-compose up
# En logs verás:
# [DEV MODE] OTP para user@example.com: 456789

# Modo asincrónico (requiere RabbitMQ)
ENABLE_ASYNC_FEATURES=true docker-compose -f docker-compose.yml -f docker-compose.rabbitmq.yml up
# En logs verás:
# [ASYNC MODE] OTP publicado a RabbitMQ para user@example.com
```

**Notas de Compatibilidad**:

- Redis sigue siendo obligatorio (almacena códigos generados)
- RabbitMQ es opcional (solo para envío async de emails)
- La interfaz de OTPService.GenerateOTP() no cambia
- Los tests de VerifyOTP siguen siendo los mismos

## COMPLETADO EN ETAPA 6: Robustez en Handlers y Type-Safe JWT Extraction

### Enhancements Implementados

La Etapa 6 mejoró significativamente la robustez del backend en Fase 8, blindando los handlers contra panics por type casting incorrecto del userID extraído del JWT. El middleware de autenticación almacena el userID del JWT como `float64` (estándar JSON), pero varios handlers intentaban usarlo directamente como `uint`, causando potenciales panics.

#### 1. Problema de Type Casting Original

**Situación anterior**: El middleware AuthMiddleware() almacena el userID desde JWT como:

```go
// En middleware/auth.go
if claims, ok := token.Claims.(jwt.MapClaims); ok {
	c.Set("userID", claims["sub"])  // claims["sub"] es float64, no uint
	c.Set("role", claims["role"])
}
```

El JWT almacena números como `float64` según especificación JSON. Sin embargo, varios handlers asumían que era `uint`:

```go
// ANTES (Etapa 5 - INSEGURO)
func (h *SocialHandler) CreateReview(c *gin.Context) {
	userID := c.GetUint("userID")  // Panic si es float64!
	// ... resto del código
}
```

**Riesgo**: Si el JWT tiene `"sub": 123` (float64), `GetUint()` retorna 0 silenciosamente, pero en algunos contextos podría causar panic o comportamiento indefinido.

#### 2. Helper Function: getUserIDSafe()

**Solución implementada en** internal/transport/http/social_handler.go:

```go
// Helper interno para obtener ID seguro (puedes moverlo a un utils.go si prefieres)
func getUserIDSafe(c *gin.Context) (uint, bool) {
	idVal, exists := c.Get("userID")
	if !exists {
		return 0, false
	}
	// Type assertion: manejar float64 o uint
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

1. **Type Assertion Explícita**: Comprueba si es `float64` (JWT standard) o `uint`
2. **Fallback Seguro**: Retorna (0, false) si no puede convertir
3. **Dual Return**: Devuelve tanto el ID como un flag de éxito (no panic)
4. **Reutilizable**: Puede moverse a `utils.go` para compartir entre handlers

#### 3. SocialHandler: CreateReview Blindado

**Implementación segura**:

```go
// CreateReview (POST /reviews)
func (h *SocialHandler) CreateReview(c *gin.Context) {
	// CORRECCIÓN DE SEGURIDAD - Etapa 6
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

	if err := h.reviewService.CreateReview(req.MatchID, userID, req.Rating, req.Comment); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Reseña guardada"})
}
```

**Flujo de seguridad**:

1. Obtener userID con `getUserIDSafe()` (maneja float64 o uint)
2. Si falla (no existe o type invalid) → 401 Unauthorized
3. Validar estructura JSON con binding
4. Llamar ReviewService con userID verificado
5. Respuesta 201 Created con confirmación

**Ventaja**: Nunca ocurre panic, siempre hay respuesta HTTP válida

#### 4. ReportHandler: Create Blindado

**Implementación segura**:

```go
func (h *ReportHandler) Create(c *gin.Context) {
	// CORRECCIÓN DE SEGURIDAD - Etapa 6
	// Replicamos la lógica segura de type casting
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

	err := h.service.CreateReport(reporterID, req.ReportedID, req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Reporte recibido. Gracias por ayudar a la comunidad."})
}
```

**Diferencia vs SocialHandler**: ReportHandler hace la conversión inline (sin refactoriz a helper). Ambos enfoques son válidos:

- **Inline (ReportHandler)**: Más verboso, pero self-contained
- **Helper (SocialHandler)**: Más DRY, requiere import de la función

**Recomendación futura**: Consolidar ambos en `internal/transport/http/utils.go`:

```go
// utils.go
package http

func GetUserIDSafe(c *gin.Context) (uint, bool) {
	idVal, exists := c.Get("userID")
	if !exists {
		return 0, false
	}
	switch v := idVal.(type) {
	case float64:
		return uint(v), true
	case uint:
		return v, true
	case int:
		return uint(v), true
	case int64:
		return uint(v), true
	case uint64:
		return uint(v), true
	default:
		return 0, false
	}
}
```

Con esto, todos los handlers usan: `userID, ok := GetUserIDSafe(c)`

#### 5. Impacto en Seguridad (R-SEC-04)

La robustez del type casting mejora R-SEC-04 (Sistema de Reportes) de dos maneras:

1. **Confiabilidad**: ReportHandler nunca puedegenerar panic por type assertion
   - Antes: `reporterID := c.GetUint()` → potencial panic si JWT mal formado
   - Después: `reporterID, ok := GetUserIDSafe()` → respuesta 401 determinística

2. **Trazabilidad**: Cada reporte vinculado correctamente a un usuario verificado
   - Si reporterID es 0 (conversión fallida), se rechaza inmediatamente
   - Previene reportes "huérfanos" o con usuario incorrecto

#### 6. Casos de Uso Mejorados

**Caso 1: Usuario válido reporta**

1. Cliente envía JWT válido con sub: 123
2. Middleware extrae claims["sub"] como float64(123)
3. ReportHandler llama GetUserIDSafe() → retorna (123, true)
4. CreateReport(123, reported_id, reason) ejecuta
5. Respuesta 201 Created

**Caso 2: JWT corrupto o malformado**

1. Cliente envía JWT con claims["sub"] = "abc" (string, no número)
2. Middleware extrae como string, c.Set("userID", "abc")
3. ReportHandler llama GetUserIDSafe() → type assertion falla en switch
4. Retorna (0, false) → sin convertir
5. `if reporterID == 0` → respuesta 401 Unauthorized

**Caso 3: Token ausente o middleware lo bloqueó**

1. Cliente no envía Authorization header
2. Middleware rechaza con 401 antes de llegar a handler
3. ReportHandler nunca se ejecuta
4. Respuesta 401 Unauthorized

#### 7. Integración con Etapa 5 (getUserIDFromContext)

En Etapa 5 se implementó `getUserIDFromContext()` en match_handler.go para extraer userID del contexto de manera segura. Etapa 6 generaliza este patrón:

- Etapa 5: Función local en match_handler.go
- Etapa 6: Helper reutilizable `getUserIDSafe()` en social_handler.go
- Futuro: Consolidar en `http/utils.go` para todos los handlers

**Evolución de seguridad**:

```
Etapa 4: c.GetUint("userID") — Inseguro (no maneja float64)
         ↓
Etapa 5: getUserIDFromContext() local — Seguro pero no reutilizable
         ↓
Etapa 6: getUserIDSafe() helper — Seguro y reutilizable
         ↓
Futuro: utils.GetUserIDSafe() — Estándar para todo el proyecto
```

#### 8. Testing de Robustez

**Test Case: JWT con float64 userID**

```go
// handlers_test.go (propuesto para Etapa 7)
func TestReportHandlerWithFloatUserID(t *testing.T) {
	// Simular JWT que devuelve float64
	router := gin.New()
	reportHandler := NewReportHandler(mockReportService)

	// Mock context con userID como float64
	ctx := &gin.Context{}
	ctx.Set("userID", float64(123))  // JWT standard: float64

	// Llamar CreateReport
	reportHandler.Create(ctx)

	// Verificar: No panic, respuesta determinística
	// (test real requeriría mock de Gin más completo)
}
```

#### 9. Lecciones Aprendidas

1. **JSON Number Ambiguity**: JSON no distingue int/uint, todo es float64
   - Solution: Type assertion explícita en handlers
   - Previene: Panics, comportamiento indefinido

2. **Middleware Data Flow**: Lo que almacena middleware debe ser consumido con cuidado
   - Antes: Asumimos type
   - Después: Verificamos type

3. **Defensive Programming**: En APIs, asumir cliente está roto
   - Antes: `GetUint()` asume formato correcto
   - Después: `GetUserIDSafe()` valida y convierte

## COMPLETADO EN ETAPA 7: Métodos Administrativos y Corrección de Identidad en Reportes

La Etapa 7 amplió significativamente el ReportService con dos nuevos métodos destinados a la administración y justicia comunitaria. Además, se corrigió un problema crítico donde los IDs de reportes no se serializaban correctamente en JSON, causando que bans se ejecutaran sobre usuarios incorrectos (IDs fantasma como 999). La Etapa 7 implementó un sistema de dos endpoints administrativos protegidos por RBAC que permiten a los administradores visualizar todos los reportes y ejecutar bans manuales con motivos documentados.

### Nuevos Métodos del ReportService (Etapa 7)

#### 1. GetAllReports() - Obtener Lista de Reportes para Admin

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
```

**Propósito**:

- Retorna **todos** los reportes en la BD (sin filtrar por estado o antigüedad)
- Carga información completa de Reporter (denunciante) y Reported (denunciado)
- Ordena por fecha descendente (más recientes primero)

**Preload Explicado**:

- `Preload("Reporter")`: GORM carga el User con ReporterID
- `Preload("Reported")`: GORM carga el User con ReportedID
- Sin Preload: reportes vendrían con solo IDs numéricos
- Con Preload: reportes incluyen {id: 2, name: "Juan", email: "..."}

**JSON Resultante** (con Preload):

```json
[
  {
    "id": 5,
    "reporter_id": 2,
    "reported_id": 3,
    "Reporter": {
      "id": 2,
      "name": "Juan Pérez",
      "email": "juan@example.com",
      "is_banned": false
    },
    "Reported": {
      "id": 3,
      "name": "Carlos García",
      "email": "carlos@example.com",
      "is_banned": false
    },
    "reason": "Solicita dinero sin entregar mascota",
    "status": "verified",
    "created_at": "2025-12-20T14:30:00Z"
  }
]
```

**Cambios en Domain** (domain/report.go):

El modelo Report en Fase 8 solo tenía IDs. Etapa 7 agregó relaciones explícitas:

```go
type Report struct {
	gorm.Model

	// IDs (Llaves Foráneas)
	ReporterID uint   `gorm:"not null" json:"reporter_id"`
	ReportedID uint   `gorm:"not null" json:"reported_id"`

	// --- RELACIONES AGREGADAS EN ETAPA 7 ---
	Reporter   User   `gorm:"foreignKey:ReporterID" json:"Reporter"`
	Reported   User   `gorm:"foreignKey:ReportedID" json:"Reported"`

	Reason     string `gorm:"not null" json:"reason"`
	Status     string `gorm:"default:'pending'" json:"status"`
}
```

**Impacto**:

- Migraciones automáticas: GORM entiende las relaciones
- Frontend recibe {Reporter: {...}, Reported: {...}} en lugar de solo IDs
- AdminDashboardScreen puede mostrar nombres sin consultas adicionales

#### 2. BanUserManual() - Ban Ejecutado por Admin

```go
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

		// Usamos FirstOrCreate para no fallar si ya estaba en blacklist
		if err := tx.Where("run = ?", user.Run).FirstOrCreate(&blacklistEntry).Error; err != nil {
			return err
		}

		return nil
	})
}
```

**Propósito**:

- Ejecuta un ban manual cuando un admin presiona el botón "BAN" en el Panel de Justicia
- Documenta quién baneó a quién y por qué
- Previene re-registro del mismo RUN

**Flujo Detallado**:

```
Entrada: adminID=1 (Alonso), targetUserID=7 (Carlos), reason="Acoso reiterado"

1. Buscar usuario por ID (targetUserID=7)
   - Si no existe: return error (ID fantasma detectado)
   - Si existe: obtener su RUN (ej: "17.234.567-K")

2. Marcar como baneado
   - UPDATE users SET is_banned=true WHERE id=7
   - Ahora AuthService.Login() rechazará este user

3. Agregar a Blacklist por RUN
   - Reason: "Baneado por Admin #1: Acoso reiterado"
   - FirstOrCreate: Si el RUN ya estaba en blacklist, ignora (no falla)
   - Previene que Carlos se registre con la misma identidad later

Resultado: Carlos García completamente fuera de PAWS
```

**Transacción ACID**:

```go
tx.Transaction(func(tx *gorm.DB) error {
	// Dentro de una transacción
	// Si ANY paso falla → TODO se revierte
	// Si todos OK → TODO se commitea
})
```

**Ventajas**:

- No hay estado intermedio (ej: baneado en users pero no en blacklist)
- Atomicidad: Todo o nada
- Seguridad: Consistencia garantizada

**Documentación del Ban**:

```
Reason: "Baneado por Admin #1: Acoso reiterado"
                    ↑               ↑
                adminID         Usuario ingresó motivo
```

Frontend puede mostrar esto en la BD:

```sql
SELECT run, reason FROM blacklist WHERE run="17.234.567-K";
-- Retorna: "Baneado por Admin #1: Acoso reiterado"
```

### AdminHandler - Exposición de Métodos (Etapa 7)

```go
type AdminHandler struct {
	service *services.ReportService
}

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
	adminIDVal, _ := c.Get("userID")
	adminID := uint(adminIDVal.(float64))

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

- `GET /admin/reports`
  - Llamaa ReportService.GetAllReports()
  - Retorna array JSON de reportes (con Preload)
- `POST /admin/ban/:id`
  - Parámetro: targetID en URL (`:id`)
  - Body: {reason: "..."}
  - Llamaa ReportService.BanUserManual()
  - Retorna: {message: "JUSTICIA APLICADA"}

**Extracción de adminID**:

```go
adminIDVal, _ := c.Get("userID")
adminID := uint(adminIDVal.(float64))
```

- AuthMiddleware almacenó "userID" como float64 (JSON standard)
- Simple conversion: `uint(float64_value)`
- (Nota: En Etapa 6 se introdujo getUserIDSafe, aquí podría usarse)

### Corrección de Identidad - El Problema de IDs Fantasma

**Problema Pre-Etapa 7**:

```
Escenario Quebrado:
1. Frontend: SocialRepository.createReport(reportedId=999, reason="Estafa")
   - reportedId=999 es un dummy (no se pasó el ID real)
2. Backend: ReportHandler.Create() crea report con reported_id=999
3. ReportService.CreateReport() verifica 3-strike y bansea ID 999
4. Admin intenta banear ID 999
5. BanUserManual busca: SELECT * FROM users WHERE id=999
6. No encuentra nada (ID fantasma, nunca existió)
7. Ban falla o genera error críptico
8. Usuario REAL (ID=5) nunca es baneado pese a reportes
```

**Problema Profundo**:

- ReportService confiaba en que reported_id siempre era correcto
- Domain.Report solo tenía ReporterID y ReportedID (sin relaciones)
- Frontend no podía visualizar qué usuario was reported (solo veía "reported_id: 999")
- Bans se aplicaban a fantasmas, usuarios reales evadían castigo

**Solución Etapa 7**:

1. **Domain mejorado**: Agregar relaciones foreignKey

   ```go
   Reporter User `gorm:"foreignKey:ReporterID"`
   Reported User `gorm:"foreignKey:ReportedID"`
   ```

2. **GetAllReports con Preload**: Cargar información completa

   ```go
   Preload("Reporter").Preload("Reported")
   ```

3. **BanUserManual valida ID**: Busca usuario, retorna error si no existe

   ```go
   var user domain.User
   if err := tx.First(&user, targetUserID).Error; err != nil {
       return err  // ID no existe → error legible
   }
   ```

4. **Frontend vé nombres**: AdminDashboardScreen muestra "Acusado: Carlos García" (no "ID 999")
   ```dart
   final reported = report['Reported']?['name'] ?? 'Usuario';
   Text("Acusado: $reported")
   ```

**Resultado**:

- No hay bans de IDs fantasma
- Admin ve claramente quién está siendo baneado
- Transacciones ACID garantizan que ban se ejecuta correctamente
- Blacklist se actualiza atómicamente

### Casos de Uso Prácticos (Etapa 7)

**Caso 1: Admin Visualiza Reportes**

```
Admin inicia sesión
  ↓
JWT contiene role="admin"
  ↓
Frontend navega a AdminDashboardScreen
  ↓
AdminDashboardScreen.initState() llamaa _refresh()
  ↓
_repo.getReports() → GET /admin/reports
  ↓
Backend: AuthMiddleware valida JWT ✓
Backend: RequireRole("admin") valida role ✓
Backend: AdminHandler.GetReports() llamaa ReportService.GetAllReports()
  ↓
ReportService.GetAllReports():
  - SELECT * FROM reports ORDER BY created_at DESC
  - Preload Reporter (nombre, email)
  - Preload Reported (nombre, email)
  ↓
Retorna JSON:
[
  {report_1 con Reporter y Reported},
  {report_2 con Reporter y Reported},
  ...
]
  ↓
Frontend FutureBuilder renderiza ListView
  ↓
Cada Card muestra:
  - Acusado: María García
  - Denunciante: Juan Pérez
  - Motivo: Solicita dinero sin entregar mascota
  - Botón: BAN
```

**Caso 2: Admin Ejecuta Ban Manual**

```
Admin presiona botón BAN en reporte de María García (ID=7)
  ↓
_banUser(7, "María García") abre AlertDialog
  ↓
Dialog: "¿Banear a María García?"
         [TextField para motivo]
  ↓
Admin ingresa: "Acoso confirmado con mensajes"
  ↓
Admin presiona "EJECUTAR SENTENCIA"
  ↓
_repo.banUser(7, "Acoso confirmado...")
  ↓
POST /admin/ban/7 {reason: "Acoso confirmado..."}
  ↓
Backend: AuthMiddleware valida JWT ✓
Backend: RequireRole("admin") valida role ✓
Backend: AdminHandler.BanUser() procesa:
  - adminID = 1 (quien ejecuta)
  - targetID = 7 (who gets banned)
  - reason = "Acoso confirmado..."
  ↓
ReportService.BanUserManual(1, 7, "Acoso..."):
  - Busca user.id=7 en BD
    ↓ ENCUENTRA user{id: 7, run: "18.123.456-K", name: "María García"}
  - UPDATE users SET is_banned=true WHERE id=7
  - INSERT blacklist(run="18.123.456-K", reason="Baneado por Admin #1: Acoso...")
  ↓
Transacción commitea (éxito)
  ↓
AdminHandler retorna: {message: "JUSTICIA APLICADA"}
  ↓
Frontend recibe 200 OK
  ↓
SnackBar: "Justicia aplicada. Usuario baneado."
  ↓
_refresh() recarga lista de reportes
  ↓
María García ya no aparece en la lista (porque está baneada y no hay nuevos reportes de ella)
  ↓
María intenta login:
  - POST /auth/login {email: "maria@example.com", password: "..."}
  - AuthService verifica blacklist por RUN
  - Encuentra: run="18.123.456-K" está en blacklist
  - 403 Forbidden: {error: "Tu cuenta ha sido suspendida"}
  - María no puede acceder a PAWS
```

### Cambios de Database (Etapa 7)

**Tabla users** (sin cambios, ya existe):

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR,
    email VARCHAR UNIQUE,
    run VARCHAR UNIQUE,
    role VARCHAR DEFAULT 'adopter',
    is_banned BOOLEAN DEFAULT FALSE,
    ...
);
```

**Tabla reports** (sin cambios en schema, solo en relaciones):

```sql
CREATE TABLE reports (
    id SERIAL PRIMARY KEY,
    reporter_id INT NOT NULL REFERENCES users(id),
    reported_id INT NOT NULL REFERENCES users(id),
    reason TEXT,
    status VARCHAR,
    created_at TIMESTAMP,
    ...
);
```

**Tabla blacklist** (sin cambios):

```sql
CREATE TABLE blacklist_entries (
    id SERIAL PRIMARY KEY,
    run VARCHAR UNIQUE,
    reason TEXT,
    created_at TIMESTAMP,
    ...
);
```

GORM AutoMigrate reconoce las nuevas relaciones sin cambiar schemas

## Estándares de Testing Fase 8

### Regla 1: Test R-SEC-04 Crítico

```go
// TestThreeStrikesBan es OBLIGATORIO para merges
// Verifica que 3 reportes = ban automático
func TestThreeStrikesBan(t *testing.T) {
    // SIEMPRE incluir:
    // 1. Setup de BD
    // 2. Crear usuarios (víctima y reporters)
    // 3. Reporte 1 y 2: verificar NO baneado
    // 4. Reporte 3: verificar SÍ baneado
}
```

### Regla 2: Tests de Seguridad en Comentarios

Si notas una posible vulnerabilidad, crea un test para validar la defensa:

```go
// TestSQLInjectionBlocked verifica que no somos vulnerables
func TestSQLInjectionBlocked(t *testing.T) {
    // Intentar: SearchUser("admin' OR '1'='1")
    // Verificar: Retorna error o resultado vacío (prepared statements)
}
```

## COMPLETADO EN ETAPA 10: Verificación OTP Asincrónica y Seguridad del Registro

### Introducción a Etapa 10 en Fase-8

La Etapa 10 introduce un sistema de verificación de identidad mediante OTP (One-Time Password) completamente integrado con la arquitectura asincrónica descrita en [Fase-14](Fase-14.md). Este sistema, aunque implementado en Etapa 10, refuerza y extiende los controles de seguridad e identidad que Fase-8 establece como base.

### Nuevos Componentes de Seguridad en Etapa 10

**OTPService (Seguridad a través del Correo Electrónico)**

El servicio OTP introduce un segundo factor de verificación sin agregar complejidad a la arquitectura:

```go
type OTPService struct {
    redisClient *redis.Client
    mqClient    *messaging.RabbitMQClient  // Puede ser nil (fallback a sync)
}

// GenerateOTP crea un código de 6 dígitos, lo almacena en Redis (5 minutos)
// y lo envía vía RabbitMQ (async) o consola (development)
func (s *OTPService) GenerateOTP(email string) (string, error) {
    code := fmt.Sprintf("%06d", rand.Intn(1000000))
    s.redisClient.Set(ctx, "otp:"+email, code, 5*time.Minute)

    event := EmailEvent{
        To:      email,
        Subject: "Tu código de verificación PAWS",
        Body:    "Código: " + code,
    }

    if s.mqClient != nil {
        s.mqClient.Publish("email_notifications", eventBytes)
    } else {
        log.Printf("[DEV MODE] OTP Code for %s: %s", email, code)
    }
    return code, nil
}

// VerifyOTP valida el código contra Redis y lo elimina tras coincidencia
func (s *OTPService) VerifyOTP(email, code string) bool {
    val, err := s.redisClient.Get(ctx, "otp:"+email).Result()
    if err != nil {
        return false
    }
    if val == code {
        s.redisClient.Del(ctx, "otp:"+email)
        return true
    }
    return false
}
```

**Por qué OTP en Etapa 10 refuerza la Fase-8:**

1. **Prevención de Registros Falsos**: Aunque Fase-8 establece validaciones de RUN, OTP añade verificación real de propiedad de correo
2. **Cumplimiento de Requisitos**: RGPD y regulaciones de privacidad requieren confirmación de correo
3. **Reducción de Spam**: Solo usuarios con acceso real a correo pueden completar registro
4. **Auditabilidad**: Cada intento de OTP se registra, facilitando investigación de intentos de abuso

### Flujo de Registro Seguro en Dos Pasos

**Etapa 1: InitiateRegistration (Almacenamiento Temporal)**

```go
type registrationCache struct {
    Name     string
    Email    string
    Password string  // Hasheada con bcrypt
    Run      string
    Role     string
}

// La contraseña se almacena hasheada, la validación de RUN ocurre
// contra la tabla de blacklist antes de persistir a Redis
func (s *AuthService) InitiateRegistration(name, email, password, run, role string) error {
    // Paso 1: Validar RUN contra blacklist (Fase-8 requiere)
    if banned, err := s.CheckBlacklist(run); banned {
        return fmt.Errorf("registro denegado: RUN en lista de exclusión")
    }

    // Paso 2: Hashear contraseña (nunca se almacena en claro)
    hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
    if err != nil {
        return err
    }

    // Paso 3: Almacenar temporalmente en Redis (10 minutos)
    tempData := registrationCache{
        Name:     name,
        Email:    email,
        Password: string(hashedPassword),
        Run:      run,
        Role:     role,
    }

    userData, _ := json.Marshal(tempData)
    s.redisClient.Set(ctx, "pending_user:"+email, userData, 10*time.Minute)

    return nil
}
```

**Etapa 2: CompleteRegistration (Persistencia tras Verificación)**

```go
// Solo después de verificar OTP exitoso, los datos se persisten
func (s *AuthService) CompleteRegistration(email string) (*domain.User, error) {
    // Paso 1: Recuperar datos temporales de Redis
    val, err := s.redisClient.Get(ctx, "pending_user:"+email).Result()
    if err == redis.Nil {
        return nil, errors.New("sesión de registro expirada")
    }

    // Paso 2: Deserializar estructura temporal
    var tempData registrationCache
    json.Unmarshal([]byte(val), &tempData)

    // Paso 3: Convertir a dominio y persistir a PostgreSQL
    user := domain.User{
        Name:     tempData.Name,
        Email:    tempData.Email,
        Password: tempData.Password,  // Ya hasheada desde paso anterior
        Run:      tempData.Run,
        Role:     tempData.Role,
    }

    if err := s.db.Create(&user).Error; err != nil {
        return nil, err
    }

    // Paso 4: Limpiar datos temporales
    s.redisClient.Del(ctx, "pending_user:"+email)

    return &user, nil
}
```

### Endpoints HTTP con Estándares de Seguridad

**POST /auth/register (Crea Sesión Temporal)**

```go
// curl -X POST http://localhost:8080/auth/register \
//   -H "Content-Type: application/json" \
//   -d '{
//     "name": "Juan García",
//     "email": "juan@example.com",
//     "password": "SecurePass123!",
//     "run": "12345678-9",
//     "role": "adopter"
//   }'

func (h *AuthHandler) Register(c *gin.Context) {
    var req RegisterRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Datos inválidos"})
        return
    }

    // Paso 1: Almacenar en Redis (validación de RUN ocurre aquí)
    if err := h.authService.InitiateRegistration(
        req.Name,
        req.Email,
        req.Password,
        req.Run,
        req.Role,
    ); err != nil {
        c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
        return
    }

    // Paso 2: Generar OTP y enviar (async o sync según config)
    h.otpService.GenerateOTP(req.Email)

    // Responder con 201 Created (indica recurso temporal creado)
    c.JSON(http.StatusCreated, gin.H{
        "message": "Código de verificación enviado a tu correo",
        "email":   req.Email,
    })
}
```

**POST /auth/otp/verify (Valida OTP y Persiste Usuario)**

```go
// curl -X POST http://localhost:8080/auth/otp/verify \
//   -H "Content-Type: application/json" \
//   -d '{
//     "email": "juan@example.com",
//     "code": "123456"
//   }'

func (h *AuthHandler) VerifyOTP(c *gin.Context) {
    var req OTPVerifyRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Datos inválidos"})
        return
    }

    // Paso 1: Validar OTP
    if !h.otpService.VerifyOTP(req.Email, req.Code) {
        c.JSON(http.StatusUnauthorized, gin.H{
            "error": "Código incorrecto o expirado",
        })
        return
    }

    // Paso 2: Completar registro (Redis → PostgreSQL)
    user, err := h.authService.CompleteRegistration(req.Email)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{
            "error": "Sesión expirada, intenta registrarte de nuevo",
        })
        return
    }

    // Paso 3: Generar JWT token
    token, err := h.authService.GenerateTokenForUser(user)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Error al generar token"})
        return
    }

    // Responder exitoso
    c.JSON(http.StatusCreated, gin.H{
        "message": "¡Bienvenido a PAWS!",
        "token":   token,
        "user": gin.H{
            "id":    user.ID,
            "name":  user.Name,
            "email": user.Email,
            "role":  user.Role,
        },
    })
}
```

### Validaciones de Seguridad Integradas

**Validación de RUN en InitiateRegistration**

```go
// Cada intento de registro verifica RUN contra blacklist
// Esto previene registros de actores maliciosos conocidos

func (s *AuthService) CheckBlacklist(run string) (bool, error) {
    var blacklisted domain.BlacklistedRUN

    // Búsqueda rápida en PostgreSQL indexada por RUN
    result := s.db.Where("run = ?", run).First(&blacklisted)

    if result.Error == gorm.ErrRecordNotFound {
        return false, nil  // RUN no está en blacklist
    }

    if result.Error != nil {
        return false, result.Error  // Error en consulta
    }

    return true, nil  // RUN está en blacklist
}
```

**Hasheo de Contraseña**

```go
// bcrypt se configura con factor de costo 10+ (defensa contra fuerza bruta)
hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), 10)

// Verificación en login (no mostrado aquí, pero sigue mismo patrón)
err := bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(providedPassword))
```

**Tolerancia HTTP 201 en Frontend**

El frontend ahora acepta tanto 200 como 201 en endpoints de registro:

```dart
// app/lib/features/auth/data/auth_repository.dart
Future<void> register({
    required String email,
    required String password,
    required String name,
    required String run,
    required String role,
}) async {
    final response = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
            'email': email,
            'password': password,
            'name': name,
            'run': run,
            'role': role,
        }),
    );

    // Aceptar 200 (legacy) y 201 (Etapa 10)
    if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Error al registrarse: ${response.body}');
    }
}
```

### Consideraciones de Testing para OTP y Seguridad

**Test: OTP Expira Correctamente**

```go
func TestOTPExpiration(t *testing.T) {
    otpService := NewOTPService(redisClient, nil)

    code, _ := otpService.GenerateOTP("test@example.com")

    // Código es válido inmediatamente
    if !otpService.VerifyOTP("test@example.com", code) {
        t.Fatal("OTP válido rechazado")
    }

    // Después de expiración, falla
    time.Sleep(6 * time.Minute)
    if otpService.VerifyOTP("test@example.com", code) {
        t.Fatal("OTP expirado aceptado")
    }
}
```

**Test: Registro Expira sin OTP**

```go
func TestRegistrationTimeoutWithoutOTP(t *testing.T) {
    authService := NewAuthService(db, redisClient)

    authService.InitiateRegistration("Juan", "juan@example.com", "pass", "12345678-9", "adopter")

    // Datos están en Redis
    _, err := authService.CompleteRegistration("juan@example.com")
    if err != nil {
        t.Fatal("Debería completarse antes de expiración")
    }

    // Después de 10 minutos, falla
    time.Sleep(11 * time.Minute)
    _, err = authService.CompleteRegistration("juan@example.com")
    if err == nil {
        t.Fatal("Debería fallar tras expiración")
    }
}
```

### Relación con Fase-8: Ampliación no Reemplazo

Etapa 10 **no reemplaza** los controles de Fase-8, sino que los **complementa**:

| Control                | Fase-8             | Etapa 10                             |
| ---------------------- | ------------------ | ------------------------------------ |
| Validación de RUN      | ✓ Contra blacklist | ✓ Aún activo en InitiateRegistration |
| Hasheo de contraseña   | ✓ bcrypt           | ✓ Aún aplica en InitiateRegistration |
| JWT con expiración     | ✓ Sí               | ✓ Generado tras OTP                  |
| Verificación de correo | ✗ No               | ✓ Nuevo mediante OTP                 |
| Token refresh          | ✓ Si se implementó | ✓ Mantiene comportamiento            |
| Rate limiting (login)  | ✓ Si se implementó | ✓ Aplica a OTP también               |

### Configuración de Etapa 10 en Distintos Ambientes

**Desarrollo (Sin RabbitMQ)**

```dotenv
# .env.development
ENABLE_ASYNC_FEATURES=false
# OTPService genera códigos y los loguea a consola
# EmailWorker no se inicia (mqClient es nil)
# Los códigos OTP aparecen en logs del servidor
```

**Staging/Producción (Con RabbitMQ)**

```dotenv
# .env.production
ENABLE_ASYNC_FEATURES=true
RABBITMQ_HOST=rabbitmq.railway.app
RABBITMQ_PORT=5672
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
SENDGRID_API_KEY=${SENDGRID_API_KEY}
# OTPService publica a RabbitMQ
# EmailWorker consume y envía via SendGrid
```

### Verificación de Implementación Correcta

Consultar [Fase-14](Fase-14.md) para detalles completos sobre:

- Arquitectura asincrónica con RabbitMQ
- Implementación de EmailWorker
- Flujo de dos pasos de registro
- Configuración de SendGrid
- Testing de componentes async
- Deployment a Railway con RabbitMQ

## COMPLETADO EN ETAPA 17: Sistema de Justicia Integral

Etapa 17 **construye sobre** los cimientos de Fase-8 transformando auto-ban automático en un sistema de justicia donde administradores tienen control y la comunidad tiene poder de verificación.

### Transición: De Auto-Ban a Justicia Administrada

**Fase-8** implementaba: 3 reportes = ban automático (ciego)

**Etapa 17** cambia a:

1. **Discrecionalidad**: Admin revisa con evidencia congelada antes de bannear
2. **Categorías**: 5 categorías estándar (abuse, scam, spam, hate, other)
3. **Blacklist Pública Opcional**: Admin decide si el ban es público
4. **Protección del Denunciante**: Silencio operativo (nunca sabe quién lo reportó)

### Modelo de Datos Extendido

**Tabla Report ampliada**:

```go
type Report struct {
    ID               uint
    ReporterID       uint       // Quién reporta
    ReportedID       uint       // Quién es reportado
    MatchID          uint       // Chat específico (contexto)

    Category         string     // NUEVO: abuse|scam|spam|hate|other
    Description      string     // NUEVO: Texto libre
    EvidenceSnapshot string     // NUEVO: JSON congelado del chat

    Status           string     // AMPLIADO: pending|resolved|dismissed
    ResolvedAt       *time.Time // NUEVO: Cuándo se resolvió
    ResolverID       *uint      // NUEVO: Admin que resolvió
}
```

**Nueva tabla: BlacklistEntry**

```go
type BlacklistEntry struct {
    Run    string `gorm:"uniqueIndex"` // RUT único
    Name   string                       // Nombre al ban
    Reason string                       // Razón pública
}
```

### Endpoints Nuevos - Etapa 17

**Administrativos (solo admin)**:

```go
GET /admin/reports              // Lista pendientes
GET /admin/reports/:id          // Detalle con evidencia
POST /admin/reports/:id/resolve // Ejecutar sentencia
```

**Público** (SIN autenticación):

```go
GET /blacklist/search?rut=...   // Búsqueda de antecedentes
```

### Características Clave

1. **Transacción Atómica**: Ban + Blacklist se ejecutan juntos o se revierten
2. **Evidencia Inmutable**: Chat congelado en JSON al momento del reporte
3. **Validación Módulo 11**: RUT chileno validado matemáticamente
4. **Silencio Operativo**: Reportado nunca sabe quién lo denunció
5. **Categorías Estandarizadas**: Admin entiende el patrón de comportamiento

### Impacto en Seguridad

**Mejora frente a Fase-8**:

- Admin no es ciego (ve el chat completo)
- Justicia es informada (contexto completo)
- Comunidad se auto-protege (verifica antes de confiar)
- Pruebas son inmutables (evidencia legal)

Para documentación completa, ver [Etapa-17](Etapa-17.md)
