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
