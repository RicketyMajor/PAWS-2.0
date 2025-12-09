# Fase 1: Núcleo de Identidad y Seguridad

## Introducción

La Fase 1 representa la implementación del corazón de PAWS: un sistema robusto de autenticación y seguridad. Todos los usuarios deben ser identificados de manera confiable antes de poder interactuar con la plataforma. Esta fase implementa las reglas de negocio críticas de seguridad (R-SEC-01, R-SEC-02 y R-SEC-03) que previenen comportamientos maliciosos.

## Objetivos de la Fase 1

1. Implementar un modelo de usuario completo con soporte para múltiples roles (adoptante, rescatista, administrador)
2. Crear un sistema de autenticación basado en JWT (JSON Web Tokens)
3. Implementar hashing de contraseñas con Bcrypt
4. Crear un sistema de blacklist para prevenir que usuarios peligrosos se registren
5. Prevenir multicuentas validando la unicidad del RUN/RUT
6. Establecer una arquitectura escalable de servicios y handlers

## Stack Tecnológico Actualizado

### Backend

- **Lenguaje**: Go 1.24.0
- **Framework Web**: Gin v1.11.0
- **ORM**: GORM v1.31.1
- **Criptografía**: golang.org/x/crypto (Bcrypt)
- **JWT**: github.com/golang-jwt/jwt/v5
- **Carga de Variables**: godotenv v1.5.1

### Base de Datos

- **PostgreSQL**: Versión 15 con PostGIS 3.3
- **Tablas Nuevas**: `users`, `blacklist_entries`

## Cambios en la Estructura del Proyecto

Comparando con la Fase 0, la estructura se ha expandido siguiendo arquitectura Clean Architecture:

```
PAWS-2.0/
├── cmd/
│   └── api/
│       └── main.go                    # Punto de entrada (ACTUALIZADO)
├── internal/
│   ├── core/                          # NUEVO: Lógica de negocio
│   │   ├── domain/
│   │   │   └── user.go               # Modelos de datos
│   │   └── services/
│   │       └── auth_service.go       # Lógica de autenticación
│   ├── transport/                     # NUEVO: Capas de comunicación
│   │   └── http/
│   │       └── auth_handler.go       # Endpoints HTTP
│   └── platform/
│       └── database/
│           └── postgres.go            # Conexión BD (ACTUALIZADO)
├── docker-compose.yml
├── go.mod                             # (ACTUALIZADO)
├── go.sum                             # (NUEVO)
├── .env                               # (ACTUALIZADO)
└── documentation/
    └── Fase-1.md                     # Este archivo
```

### Explicación de Nueva Arquitectura

Hemos adoptado una arquitectura en capas que separa responsabilidades:

**`/internal/core/domain/`**: Modelos y estructuras de datos

- Contiene las definiciones de Usuario y BlacklistEntry
- Sin lógica de negocio, solo estructuras

**`/internal/core/services/`**: Lógica de negocio pura

- Implementa casos de uso (registro, login)
- No conoce detalles de HTTP o BD (la BD se inyecta)
- Reutilizable en diferentes contextos (HTTP, CLI, etc.)

**`/internal/transport/http/`**: Adapters para HTTP

- Maneja serialización/deserialización JSON
- Valida requests usando Gin
- Mapea requests/responses a llamadas de servicios

**`/internal/platform/database/`**: Infraestructura técnica

- Gestiona conexión a PostgreSQL
- Ejecuta migraciones

Este patrón permite testear lógica sin servidor HTTP, cambiar frameworks fácilmente, y mantener código limpio.

## Detalles Técnicos Implementados

### 1. Modelo de Datos (domain/user.go)

```go
type User struct {
    gorm.Model
    Name       string
    Email      string // uniqueIndex
    Run        string // uniqueIndex - RUN/RUT de Chile
    Password   string
    Role       string // "adopter", "rescuer", "admin"
    IsVerified bool   // OCR verificado
    IsBanned   bool   // Bloqueado por seguridad
}

type BlacklistEntry struct {
    gorm.Model
    Run    string // uniqueIndex
    Reason string
}
```

**GORM Features Utilizadas**:

- `gorm.Model`: Inyecta ID, CreatedAt, UpdatedAt, DeletedAt (soft delete)
- `uniqueIndex`: Crea índice único en BD para evitar duplicados
- `json:"field"` / `json:"-"`: Control de serialización JSON
- `not null`: Constraint en la BD

**Decisiones de Seguridad**:

1. **Email y RUN únicos**: Previenen duplicación de cuentas
2. **`json:"-"` en Password**: Asegura que nunca se envíe el hash al cliente por error
3. **IsVerified y IsBanned**: Flags para control de estado del usuario
4. **BlacklistEntry separada**: Tabla aparte para realizar bloqueos preventivos

### 2. Servicio de Autenticación (services/auth_service.go)

El `AuthService` implementa los casos de uso críticos:

#### Función Register

```go
func (s *AuthService) Register(name, email, password, run, role string) (*domain.User, error)
```

**Flujo de Validación Implementado**:

1. **R-SEC-03 (Blacklist Check)**:

```go
var blacklistEntry domain.BlacklistEntry
if err := database.DB.Where("run = ?", run).First(&blacklistEntry).Error; err == nil {
    return nil, errors.New("registro rechazado: este RUN se encuentra en nuestra lista de bloqueo por: " + blacklistEntry.Reason)
}
```

Antes de permitir registro, consultamos si el RUN está en la blacklist. Si está, rechazamos inmediatamente.

2. **R-SEC-02 (Prevención de Multicuentas por RUN)**:

```go
var existingUser domain.User
result := database.DB.Where("run = ?", run).First(&existingUser)
if result.Error == nil {
    return nil, errors.New("el RUN ya está registrado en el sistema")
}
```

Validamos que no exista otro usuario con el mismo RUN.

3. **Validación de Email único**:
   Similar al RUN, evitamos emails duplicados.

4. **Hashing de Contraseña con Bcrypt**:

```go
hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
```

Bcrypt es una función hash criptográfica lenta y adaptativa:

- **Lento**: Toma ~100ms por hash (imposible hacer ataques de fuerza bruta)
- **Adaptativo**: El costo se puede aumentar si el hardware mejora
- **Salted**: Incluye salt automáticamente

5. **Creación del Usuario**:
   Se guarda con todos los flags en estado inicial (no verificado, no baneado).

#### Función Login

```go
func (s *AuthService) Login(email, password string) (string, error)
```

**Flujo de Autenticación**:

1. **Búsqueda de Usuario**:

```go
var user domain.User
result := database.DB.Where("email = ?", email).First(&user)
```

Buscamos el usuario por email. Si no existe, decimos "credenciales inválidas" (no decimos "usuario no existe" por seguridad).

2. **R-SEC-03 (Validación de Baneo)**:

```go
if user.IsBanned {
    return "", errors.New("tu cuenta ha sido suspendida por violar las normas de seguridad")
}
```

Si el usuario está marcado como baneado, rechazamos el login.

3. **Verificación de Contraseña**:

```go
err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password))
```

Comparamos el hash almacenado con el hash de la contraseña proporcionada. Bcrypt hace esto de manera segura contra timing attacks.

4. **Generación de JWT**:

```go
token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
    "sub":  user.ID,
    "role": user.Role,
    "exp":  time.Now().Add(time.Hour * 24).Unix(),
})

tokenString, err := token.SignedString([]byte(secret))
```

**Estructura del JWT**:
Un JWT consta de tres partes separadas por puntos: `header.payload.signature`

- **Header**: Especifica algoritmo (HS256 = HMAC SHA-256)
- **Payload**: Datos codificados en Base64 (claims)
- **Signature**: HMAC de las dos partes anteriores con clave secreta

**Claims Incluidos**:

- `sub` (subject): ID del usuario
- `role`: Rol para autorización posterior
- `exp`: Timestamp de expiración (24 horas)

**Flujo de Verificación Posterior**:
En futuras fases, un middleware verificará que cada request incluya un JWT válido:

```go
token, err := jwt.ParseWithClaims(tokenString, &jwt.MapClaims{}, func(token *jwt.Token) (interface{}, error) {
    return []byte(secret), nil
})
if !token.Valid {
    return http.StatusUnauthorized
}
```

### 3. Handler HTTP (transport/http/auth_handler.go)

Los handlers son la frontera entre HTTP y servicios. Utilizan Gin para manejo elegante.

#### RegisterRequest y LoginRequest

```go
type RegisterRequest struct {
    Name     string `json:"name" binding:"required"`
    Email    string `json:"email" binding:"required,email"`
    Password string `json:"password" binding:"required,min=6"`
    Run      string `json:"run" binding:"required"`
    Role     string `json:"role" binding:"required,oneof=adopter rescuer"`
}
```

**Validaciones de Gin**:

- `binding:"required"`: Campo obligatorio
- `binding:"email"`: Formato de email válido
- `binding:"min=6"`: Mínimo 6 caracteres
- `binding:"oneof=adopter rescuer"`: Solo dos valores permitidos

Si la validación falla, Gin automáticamente retorna 400 con error.

#### Función Register (Handler)

```go
func (h *AuthHandler) Register(c *gin.Context) {
    var req RegisterRequest

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    user, err := h.service.Register(req.Name, req.Email, req.Password, req.Run, req.Role)
    if err != nil {
        c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusCreated, gin.H{
        "message": "Usuario registrado exitosamente",
        "user_id": user.ID,
    })
}
```

**Flujo**:

1. Parse JSON request
2. Validar estructura
3. Llamar servicio
4. Retornar respuesta HTTP con código apropiado

**Códigos HTTP Utilizados**:

- `201 Created`: Registro exitoso (recurso creado)
- `400 Bad Request`: JSON inválido
- `409 Conflict`: Violación de constraints (RUN duplicado, etc.)

#### Función Login (Handler)

Similar a Register, pero retorna el token:

```go
c.JSON(http.StatusOK, gin.H{
    "token": token,
})
```

### 4. Punto de Entrada Actualizado (cmd/api/main.go)

```go
func main() {
    // 1. Cargar .env
    if err := godotenv.Load(); err != nil {
        log.Fatal("Error cargando .env")
    }

    // 2. Conectar BD
    database.Connect()
    database.Migrate()

    // 3. Inyección de dependencias
    authService := services.NewAuthService()
    authHandler := transport.NewAuthHandler(authService)

    // 4. Configurar Gin
    r := gin.Default()

    // 5. Definir rutas
    api := r.Group("/api/v1")
    {
        auth := api.Group("/auth")
        {
            auth.POST("/register", authHandler.Register)
            auth.POST("/login", authHandler.Login)
        }
    }

    // 6. Arrancar
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    log.Printf("🚀 Servidor PAWS corriendo en puerto %s", port)
    r.Run(":" + port)
}
```

**Cambios Clave**:

1. **Inyección de Dependencias Manual**: Creamos instancias e inyectamos
2. **Versionamiento de API**: Rutas bajo `/api/v1` (buena práctica para evitar breaking changes)
3. **Grouping de Rutas**: Organización lógica de endpoints

### 5. Migraciones Automáticas (database/postgres.go)

Se añadió función `Migrate()`:

```go
func Migrate() {
    err := database.DB.AutoMigrate(&domain.User{}, &domain.BlacklistEntry{})
    if err != nil {
        log.Fatal("❌ Error en la migración de base de datos: ", err)
    }
    log.Println("✅ Migración de base de datos completada")
}
```

**Cómo funciona GORM AutoMigrate**:

GORM inspecciona el struct y automáticamente:

1. Crea tablas si no existen
2. Añade columnas faltantes
3. Respeta constraints (`uniqueIndex`, `not null`, etc.)

**Seguridad**: Nunca elimina columnas ni tablas (destructivo).

### 6. Archivo .env Actualizado

```env
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

**Nueva Variable**:

- `JWT_SECRET`: Clave para firmar/verificar tokens JWT. En producción, debe ser una cadena aleatoria segura de 32+ caracteres.

## Pruebas de Endpoints

### Registro (POST /api/v1/auth/register)

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

**Respuesta Exitosa (201)**:

```json
{
  "message": "Usuario registrado exitosamente",
  "user_id": 1
}
```

**Respuesta Error - RUN Duplicado (409)**:

```json
{
  "error": "el RUN ya está registrado en el sistema"
}
```

### Login (POST /api/v1/auth/login)

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "juan@example.com",
    "password": "securepassword123"
  }'
```

**Respuesta Exitosa (200)**:

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MzMzMzMzMzMsInJvbGUiOiJhZG9wdGVyIiwic3ViIjoxfQ.abc123..."
}
```

**Respuesta Error - Credenciales Inválidas (401)**:

```json
{
  "error": "credenciales inválidas"
}
```

## Cambios Detectados desde Fase 0

| Cambio            | Ubicación                                 | Descripción                   |
| ----------------- | ----------------------------------------- | ----------------------------- |
| Nueva dependencia | `go.mod`                                  | Gin v1.11.0 (framework web)   |
| Nueva dependencia | `go.mod`                                  | golang.org/x/crypto (Bcrypt)  |
| Nueva dependencia | `go.mod`                                  | github.com/golang-jwt/jwt/v5  |
| Nueva carpeta     | `internal/core/domain/`                   | Modelos de datos              |
| Nueva carpeta     | `internal/core/services/`                 | Lógica de negocio             |
| Nueva carpeta     | `internal/transport/http/`                | Handlers HTTP                 |
| Nuevo archivo     | `internal/core/domain/user.go`            | Modelo User y BlacklistEntry  |
| Nuevo archivo     | `internal/core/services/auth_service.go`  | Casos de uso de autenticación |
| Nuevo archivo     | `internal/transport/http/auth_handler.go` | Endpoints HTTP                |
| Actualizado       | `cmd/api/main.go`                         | Configuración Gin y rutas     |
| Actualizado       | `internal/platform/database/postgres.go`  | Función Migrate() añadida     |
| Actualizado       | `.env`                                    | Nueva variable JWT_SECRET     |
| Nuevo archivo     | `go.sum`                                  | Lock file de dependencias     |

## Decisiones Arquitectónicas Importantes

### 1. Separación Domain/Service/Handler

**Razón**: Permite testear lógica sin HTTP, reutilizar servicios, cambiar frameworks.

**Ejemplo Future-Proof**:

```go
// Mismo servicio para CLI
authCLI := services.NewAuthService()
user, err := authCLI.Register("Juan", "juan@example.com", "pass", "12345678-9", "adopter")

// Mismo servicio para gRPC
grpcServer := grpc.NewAuthServer(authService)
```

### 2. JWT con HS256

**Ventajas**:

- Stateless: No requiere almacenar sesiones en BD
- Escalable: Múltiples servidores verifican sin coordinación
- Estándar: Soportado por librerías en todos los lenguajes

**Desventajas**:

- No se puede "invalidar" instantáneamente (esperar a expiración)
- Solución futura: Redis token blacklist

### 3. Bcrypt vs SHA256 o MD5

| Hash   | Velocidad     | Seguridad                               |
| ------ | ------------- | --------------------------------------- |
| MD5    | Muy rápido    | Roto (no usar)                          |
| SHA256 | Rápido        | Débil para passwords (atacable con GPU) |
| Bcrypt | Lento (100ms) | Fuerte (adaptativo)                     |

Bcrypt es obligatorio para passwords por su factor de trabajo ajustable.

### 4. Blacklist en BD vs Redis

**Implementación Actual (BD)**:

- Consulta BD en cada registro
- Seguro pero potencialmente lento si BD está saturada

**Mejora Futura (Redis)**:
En Fase 1.5:

```go
// Cachear blacklist en Redis
redis.Set("blacklist:"+run, true, 24*time.Hour)

// Consultar primero Redis (muy rápido)
if redis.Exists("blacklist:"+run) {
    return nil, errors.New("usuario bloqueado")
}
// Si no está en caché, consultar BD
```

### 5. Variable Global DB

**Limitación Actual**: Variable global en `database.go`

**Plan de Refactorización (Fase 2)**:
Inyectar BD como parámetro:

```go
type AuthService struct {
    db *gorm.DB
}

func NewAuthService(db *gorm.DB) *AuthService {
    return &AuthService{db: db}
}

func (s *AuthService) Register(...) {
    s.db.Create(&user)
}
```

Esto facilita testeo (mock de BD) y múltiples conexiones.

## Implementación de Reglas de Seguridad

### R-SEC-01: Verificación de Identidad (OCR)

**Estado Fase 1**: Preparado pero no implementado

- Campo `IsVerified` en User
- En Fase 2 se conectará servicio OCR mock
- Login rechazará usuarios no verificados cuando esté habilitado

```go
// Código future que se activará en Fase 2
if user.Role == "rescuer" && !user.IsVerified {
    return "", errors.New("debes verificar tu identidad antes de publicar mascotas")
}
```

### R-SEC-02: Prevención de Multicuentas

**Status Fase 1**: Implementado completamente

```go
// Validar RUN único
result := database.DB.Where("run = ?", run).First(&existingUser)
if result.Error == nil {
    return nil, errors.New("el RUN ya está registrado en el sistema")
}
```

### R-SEC-03: Blacklist y Baneo

**Status Fase 1**: Implementado en BD

Verificación en registro:

```go
var blacklistEntry domain.BlacklistEntry
if err := database.DB.Where("run = ?", run).First(&blacklistEntry).Error; err == nil {
    return nil, errors.New("registro rechazado...")
}
```

Verificación en login:

```go
if user.IsBanned {
    return "", errors.New("tu cuenta ha sido suspendida...")
}
```

**Mejora Futura**: Consultar Redis primero para performance.

## Próximos Pasos (Fase 2)

1. **Middleware de Autenticación**: Proteger endpoints con JWT
2. **CRUD de Mascotas**: Endpoints para crear/editar fichas
3. **Upload de Imágenes**: Implementar subida a MinIO
4. **OCR Mock**: Servicio para validar DNI
5. **Testing Unitario**: Tests de auth_service.go
6. **Logging Estructurado**: Cambiar `log` a `slog` o similar

## Stack de Dependencias Completo

| Paquete             | Versión | Propósito                    | Fase Añadido |
| ------------------- | ------- | ---------------------------- | ------------ |
| godotenv            | v1.5.1  | Variables de entorno         | Fase 0       |
| gorm                | v1.31.1 | ORM para BD                  | Fase 0       |
| driver/postgres     | v1.6.0  | Driver GORM PostgreSQL       | Fase 0       |
| pgx                 | v5.6.0  | Driver bajo nivel PostgreSQL | Fase 0       |
| gin                 | v1.11.0 | Framework web                | Fase 1       |
| golang.org/x/crypto | v0.46.0 | Bcrypt y criptografía        | Fase 1       |
| jwt/v5              | v5.3.0  | JSON Web Tokens              | Fase 1       |

## Referencias

- JWT.io: https://jwt.io
- GORM Docs: https://gorm.io
- Gin Docs: https://gin-gonic.com
- Bcrypt Explanation: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- Clean Architecture: https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html
