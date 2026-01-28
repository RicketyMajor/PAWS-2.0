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
    log.Printf("[START] Servidor PAWS corriendo en puerto %s", port)
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
        log.Fatal("[ERROR] Error en la migración de base de datos: ", err)
    }
    log.Println("[SUCCESS] Migración de base de datos completada")
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

## Actualización Etapa 1: CORS para Frontend Web (Flutter Web)

A partir de la Etapa 1 de Operación PAWS Real, se ha implementado soporte explícito para CORS (Cross-Origin Resource Sharing) permitiendo que el frontend Flutter Web se conecte al backend desde navegadores.

### Problema Resuelto

Cuando un navegador ejecuta JavaScript/Flutter Web, las peticiones HTTP deben tener explícitamente autorización del servidor mediante headers CORS. Sin esto, el navegador bloqueará las peticiones como originadas desde un sitio no autorizado.

Error común sin CORS:

```
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

### Middleware CORSMiddleware

Se ha implementado `internal/transport/http/middleware/cors.go`:

```go
package middleware

import (
    "net/http"
    "github.com/gin-gonic/gin"
)

func CORSMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Permitir cualquier origen (ajustable en producción)
        c.Writer.Header().Set("Access-Control-Allow-Origin", "*")

        // Permitir credenciales (cookies, auth headers)
        c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")

        // Headers permitidos (necesitamos Authorization para JWT)
        c.Writer.Header().Set(
            "Access-Control-Allow-Headers",
            "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With",
        )

        // Métodos HTTP permitidos
        c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

        // Manejo de solicitud OPTIONS (Preflight)
        // El navegador pregunta "¿Puedo hablar contigo?" antes de enviar datos reales
        if c.Request.Method == "OPTIONS" {
            c.AbortWithStatus(http.StatusNoContent)
            return
        }

        c.Next()
    }
}
```

### Aplicación en main.go

En `cmd/api/main.go`, el middleware se aplica ANTES de definir rutas:

```go
func main() {
    database.Connect()

    // ... inicializar servicios ...

    r := gin.Default()

    // APLICAR CORS: Fundamental para Flutter Web (Etapa 1)
    r.Use(middleware.CORSMiddleware())

    r.Static("/uploads", "./uploads")

    api := r.Group("/api/v1")
    {
        // Rutas públicas...
        auth := api.Group("/auth")
        {
            auth.POST("/register", authHandler.Register)
            auth.POST("/login", authHandler.Login)
        }
    }

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    log.Printf("[START] Servidor PAWS corriendo en puerto %s", port)
    r.Run(":" + port)
}
```

### Ventajas de esta Implementación

1. **Flutter Web Compatible**: Aplicación web puede consumir API sin errores CORS
2. **Seguridad Flexible**: Permite todos los orígenes para desarrollo, configurable en producción
3. **JWT Headers**: Autoriza explícitamente el header Authorization necesario para tokens JWT
4. **Preflight Handling Automático**: Responde correctamente a solicitudes OPTIONS del navegador
5. **Ubicación Centralizada**: Un solo middleware aplica CORS a todas las rutas

### Configuración en Producción

Para restringir CORS a un dominio específico (ej: Vercel):

```go
c.Writer.Header().Set("Access-Control-Allow-Origin", "https://tuapp.vercel.app")
```

Implementar lista de dominios permitidos:

```go
allowedOrigins := []string{
    "http://localhost:3000",
    "https://tuapp.vercel.app",
    "https://www.tuapp.com",
}

origin := c.Request.Header.Get("Origin")
for _, allowed := range allowedOrigins {
    if origin == allowed {
        c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
        break
    }
}
```

### Impacto en Desarrollo

- **Fase 5 (Frontend Flutter)**: Flutter Web ahora puede hacer peticiones HTTP sin bloqueos
- **Todas las Fases (2-10)**: Todos los endpoints habilitados automáticamente para CORS
- **Etapa 5 (Despliegue)**: Se puede ajustar política según entorno (desarrollo vs producción)
- **Testing**: Frontend y Backend pueden ejecutarse en puertos diferentes sin conflictos

## Actualización Etapa 1: CORS para Frontend Web (Flutter Web)

A partir de la Etapa 1 de Operación PAWS Real, se ha implementado soporte explícito para CORS (Cross-Origin Resource Sharing) permitiendo que el frontend Flutter Web se conecte al backend desde navegadores.

### Problema Resuelto

Cuando un navegador ejecuta JavaScript/Flutter Web, las peticiones HTTP deben tener explícitamente autorización del servidor mediante headers CORS. Sin esto, el navegador bloqueará las peticiones como originadas desde un sitio no autorizado.

Error común sin CORS:

```
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

### Middleware CORSMiddleware

Se ha implementado `internal/transport/http/middleware/cors.go`:

```go
package middleware

import (
    "net/http"
    "github.com/gin-gonic/gin"
)

func CORSMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Permitir cualquier origen (ajustable en producción)
        c.Writer.Header().Set("Access-Control-Allow-Origin", "*")

        // Permitir credenciales (cookies, auth headers)
        c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")

        // Headers permitidos (necesitamos Authorization para JWT)
        c.Writer.Header().Set(
            "Access-Control-Allow-Headers",
            "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With",
        )

        // Métodos HTTP permitidos
        c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

        // Manejo de solicitud OPTIONS (Preflight)
        // El navegador pregunta "¿Puedo hablar contigo?" antes de enviar datos reales
        if c.Request.Method == "OPTIONS" {
            c.AbortWithStatus(http.StatusNoContent)
            return
        }

        c.Next()
    }
}
```

### Aplicación en main.go

En `cmd/api/main.go`, el middleware se aplica ANTES de definir rutas:

```go
func main() {
    database.Connect()

    // ... inicializar servicios ...

    r := gin.Default()

    // APLICAR CORS: Fundamental para Flutter Web (Etapa 1)
    r.Use(middleware.CORSMiddleware())

    r.Static("/uploads", "./uploads")

    api := r.Group("/api/v1")
    {
        // Rutas públicas...
        auth := api.Group("/auth")
        {
            auth.POST("/register", authHandler.Register)
            auth.POST("/login", authHandler.Login)
        }
    }

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    log.Printf("[START] Servidor PAWS corriendo en puerto %s", port)
    r.Run(":" + port)
}
```

### Ventajas de esta Implementación

1. **Flutter Web Compatible**: Aplicación web puede consumir API sin errores CORS
2. **Seguridad Flexible**: Permite todos los orígenes para desarrollo, configurable en producción
3. **JWT Headers**: Autoriza explícitamente el header Authorization necesario para tokens JWT
4. **Preflight Handling Automático**: Responde correctamente a solicitudes OPTIONS del navegador
5. **Ubicación Centralizada**: Un solo middleware aplica CORS a todas las rutas

### Configuración en Producción

Para restringir CORS a un dominio específico (ej: Vercel):

```go
c.Writer.Header().Set("Access-Control-Allow-Origin", "https://tuapp.vercel.app")
```

Implementar lista de dominios permitidos:

```go
allowedOrigins := []string{
    "http://localhost:3000",
    "https://tuapp.vercel.app",
    "https://www.tuapp.com",
}

origin := c.Request.Header.Get("Origin")
for _, allowed := range allowedOrigins {
    if origin == allowed {
        c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
        break
    }
}
```

### Impacto en Desarrollo

- **Fase 5 (Frontend Flutter)**: Flutter Web ahora puede hacer peticiones HTTP sin bloqueos
- **Todas las Fases (2-10)**: Todos los endpoints habilitados automáticamente para CORS
- **Etapa 5 (Despliegue)**: Se puede ajustar política según entorno (desarrollo vs producción)
- **Testing**: Frontend y Backend pueden ejecutarse en puertos diferentes sin conflictos

## COMPLETADO EN ETAPA 7: RBAC (Role-Based Access Control) y Autopromoción Administrativa

La Etapa 7 amplió el modelo de usuario y el flujo de autenticación para soportar un tercer rol administrativo ("admin") con mecanismos de autopromoción automática y protección de rutas sensibles. Aunque el User model ya contemplaba "admin" como rol posible en su definición (comentario en linea 100), la Etapa 7 implementa la infraestructura completa para hacer que este rol sea funcional y seguro.

### Cambios en Fase-1 Impactados por Etapa 7

#### 1. Ampliación del Modelo de Roles

El User model de Fase 1 soportaba teóricamente tres roles: "adopter", "rescuer", y "admin". La Etapa 7 activa el rol "admin":

**Contexto Histórico**:

- Fase 1: Model define Role como string sin restricción (comentario menciona "adopter", "rescuer", "admin")
- Etapa 7: Implementa infraestructura para que el rol "admin" sea funcional y seguro

**Roles Operacionales en PAWS (Etapa 7)**:

1. **adopter** (Adoptante): Usuario que busca adoptar mascota. Default para registros normales.
   - Acceso: GET mascotas, POST swipes, GET matches, POST reviews/reports, WebSocket chat
   - Negado: GET /admin/_, POST /admin/_

2. **rescuer** (Rescatista): Usuario que rescata y ofrece mascotas en adopción. Default para registros normales.
   - Acceso: GET mascotas, GET solicitudes, POST respuestas, GET matches, POST reviews/reports, WebSocket chat
   - Negado: GET /admin/_, POST /admin/_

3. **admin** (Administrador): Usuario con poderes de moderación. Asignado vía autopromoción en Etapa 7.
   - Acceso: Todos los endpoints de mortales + GET /admin/reports + POST /admin/ban/:id
   - Negado: Ninguno (omnipotente en la plataforma)

**Valores Válidos**:

- RegisterRequest en Fase 1 valida: `binding:"oneof=adopter rescuer"` (solo mortales, correcto)
- Database en Fase 1 acepta cualquier string: `Role string` (correcto, permite future-proofing)
- AuthService en Fase 1 asigna: `role: "adopter"` por default (correcto)
- Etapa 7 asigna "admin" via seeder en main.go (nuevo)

#### 2. JWT Extendido con Campo Role (Etapa 7)

Fase 1 generaba JWT con claims mínimos (sub, iat, exp). Etapa 7 extiende el JWT con el campo "role":

**JWT Antiguo (Fase 1-6)**:

```json
{
  "sub": 123,
  "iat": 1640000000,
  "exp": 1640003600,
  ...
}
```

**JWT Extendido (Etapa 7)**:

```json
{
  "sub": 123,
  "role": "adopter",
  "iat": 1640000000,
  "exp": 1640003600,
  ...
}
```

**Impacto en AuthService** (internal/core/services/auth_service.go):

- AuthService.Login() y Register() ahora incluyen role en JWT al generar el token
- Frontend decodifica JWT (JwtDecoder.decode) y extrae rol
- LoginScreen usa role para decidir navegación: admin → AdminDashboardScreen, mortal → MainLayoutScreen

**Generación del JWT con Role** (AuthService):

```go
claims := jwt.MapClaims{
    "sub":  user.ID,
    "role": user.Role,  // NUEVO EN ETAPA 7
    "iat":  time.Now().Unix(),
    "exp":  time.Now().Add(24 * time.Hour).Unix(),
}
```

#### 3. Seeder de Autopromoción (main.go - Etapa 7)

Implementado en cmd/api/main.go después de AutoMigrate():

```go
// SEEDER DE ADMIN (Auto-Promoción)
var adminUser domain.User
targetEmail := "alonso.vera@mail.udp.cl"

if err := database.DB.Where("email = ?", targetEmail).First(&adminUser).Error; err == nil {
    if adminUser.Role != "admin" {
        database.DB.Model(&adminUser).Update("role", "admin")
        log.Printf("Usuario %s promovido a ADMIN.", targetEmail)
    }
} else {
    log.Printf("AVISO: El usuario %s aún no existe. Regístrate y reinicia.", targetEmail)
}
```

**Ventajas del Seeder vs Endpoint**:

| Approach                      | Ventaja                                    | Desventaja                                        |
| ----------------------------- | ------------------------------------------ | ------------------------------------------------- |
| Endpoint POST /admin/register | Flexible, UI para crear admins             | Requiere protección adicional, riesgo de escalada |
| Seeder en main.go             | Determinista, sin endpoint público, seguro | Solo un admin, requiere restart                   |
| **Seeder (Elegido)**          | **Perfecto para MVP, no expone API**       | **Limitado a un email**                           |

**Flujo del Seeder**:

```
Evento 1: Alonso se registra via app (email: alonso.vera@mail.udp.cl)
  → AuthService.Register() crea User con role="adopter"
  → BD: INSERT users(role="adopter")
  → JWT: {sub: 1, role: "adopter"}
  → Frontend: MainLayoutScreen (user normal)

Evento 2: Developer reinicia backend
  → main.go inicia
  → AutoMigrate crea tablas
  → Seeder ejecuta: WHERE email = "alonso.vera@mail.udp.cl"
  → Encuentra registro (id=1)
  → UPDATE users SET role="admin" WHERE id=1
  → Log: "Usuario alonso.vera@mail.udp.cl promovido a ADMIN"

Evento 3: Alonso hace login nuevamente
  → AuthService.Login() genera JWT con user.Role = "admin"
  → JWT: {sub: 1, role: "admin"}
  → Frontend decodifica: role=="admin"
  → Navega a AdminDashboardScreen en lugar de MainLayoutScreen
```

#### 4. Política de Roles en Endpoints (Etapa 7)

No hay cambios en Fase 1 directamente, pero Etapa 7 implementa política: Fase 1 solo autentica (¿usuario válido?), Etapa 7 autoriza además (¿usuario tiene rol requerido?).

**Flujo Pre-Etapa 7 (Fase 1-6)**:

```
Request con JWT
  ↓
AuthMiddleware: ¿Token válido? (Fase 1)
  ↓
Handler (IF user valid → execute)
```

**Flujo Post-Etapa 7 (Etapa 7)**:

```
Request con JWT
  ↓
AuthMiddleware: ¿Token válido? (Fase 1)
  ↓
RequireRole("admin"): ¿user.role == "admin"? (Etapa 7)
  ↓
Handler (IF both valid → execute)
```

**Implicación para Fase 1**:

- Ningún cambio en código de Fase 1 necesario
- El rol se extrae ya desde el JWT en AuthMiddleware
- Etapa 7 agrega middleware adicional (RequireRole) que se compone con AuthMiddleware
- Backward compatible: endpoints sin RequireRole() siguen funcionando para todos

### Seguridad de RBAC en Contexto de Fase-1

Fase-1 Establece la fundación de seguridad (autenticación + hashing), Etapa 7 añade la autorización:

**Pilares de Seguridad (Fase 1)**:

1. Contraseñas hasheadas con Bcrypt
2. JWT con firma HMAC
3. Verificación de token en AuthMiddleware
4. BlacklistEntry para prevenir re-registro

**Pilares de Seguridad (Etapa 7 - Nuevos)**:

5. Role en JWT para distinguir niveles de acceso
6. RequireRole() middleware para proteger endpoints administrativos
7. Autopromoción determinista (no endpoint público)
8. Doble guardián: Auth + Role (no solo Auth)

**Cadena de Confianza**:

```
Contraseña → Bcrypt Hash
           ↓
        Login exitoso
           ↓
        JWT generado con role
           ↓
      JWT Validado (sig HMAC)
           ↓
      Role extraído del JWT
           ↓
    RequireRole() verifica
           ↓
   Acceso a recurso admin
```

### Implicaciones para Upgrade de Usuarios Existentes (Etapa 7)

Si la BD ya existe con usuarios sin campo "role" (pre-Fase 1 fix):

**Problema**:

```sql
SELECT * FROM users WHERE id=1;
-- Retorna: role = NULL o "" (vacío)
```

**Solución (Ya implementada en Fase 1)**:

```go
type User struct {
    ...
    Role string `gorm:"default:'adopter'"`  // Default en DB
    ...
}
```

GORM AutoMigrate agrega columna con default. Usuarios existentes heredan "adopter" automáticamente.

**Para Etapa 7**:

```sql
-- Manual check (si necesario)
UPDATE users SET role='adopter' WHERE role IS NULL OR role='';

-- Luego ejecutar seeder en main.go
-- Solo alonso.vera@mail.udp.cl será promocionado a admin
```

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

## COMPLETADO EN ETAPA 19: Módulo de Doble Identidad - Flexibilidad en Restricciones de Base de Datos

Etapa 19 resuelve una limitación crítica de Fase 1: los índices `UNIQUE` globales bloqueaban completamente la doble identidad. La solución implementa índices compuestos que permiten flexibilidad sin sacrificar unicidad.

### Cambios en el Modelo de Usuario (Etapa 19)

**Antes (Fase 1 - Restricción Global)**:

```go
type User struct {
    Email string `gorm:"uniqueIndex"`  // GLOBAL: No puede repetirse
    Run   string `gorm:"uniqueIndex"`  // GLOBAL: No puede repetirse
    Role  string `gorm:"default:'adopter'"`
}
```

**Después (Etapa 19 - Índices Compuestos)**:

```go
type User struct {
    Email string `gorm:"index:idx_email_role,unique;not null"`  // COMPUESTO: (Email, Role)
    Run   string `gorm:"index:idx_run_role,unique;not null"`    // COMPUESTO: (Run, Role)
    Role  string `gorm:"default:'adopter';index:idx_email_role,unique;index:idx_run_role,unique"`
}
```

**Garantía**: Ahora la base de datos permite:

- (Email=juan@mail.com, Role=adopter)
- (Email=juan@mail.com, Role=rescuer)

Ambas coexisten sin conflicto porque el rol es parte de la clave única compuesta.

### Limpieza Automática de Índices Legacy

El servidor implementa `dropLegacyConstraints()` en `cmd/api/main.go`, que ejecuta ANTES de AutoMigrate():

```go
func dropLegacyConstraints(db *gorm.DB) {
    queries := []string{
        "DROP INDEX IF EXISTS idx_users_run;",
        "DROP INDEX IF EXISTS idx_users_email;",
        "DROP INDEX IF EXISTS uni_users_run;",
        "DROP INDEX IF EXISTS uni_users_email;",
    }

    log.Println("MIGRACIÓN: Limpiando restricciones antiguas...")
    for _, q := range queries {
        if err := db.Exec(q).Error; err != nil {
            log.Printf("Advertencia borrando índice (%s): %v", q, err)
        }
    }
}
```

**Garantía**: Operadores NO necesitan intervención manual. El servidor limpia índices antiguos automáticamente en el startup, preparando la BD para los nuevos índices compuestos.

### Lógica de Duplicidad Inteligente

La función `InitiateRegistration()` en `internal/core/services/auth_service.go` se actualiza:

```go
func (s *AuthService) InitiateRegistration(name, email, password, run, role string) error {
    roleNormalized := strings.ToLower(role)
    if roleNormalized == "" { roleNormalized = "adopter" }

    // CAMBIO: Verificar existencia ESPECÍFICA para este Rol
    var existingUser domain.User
    err := s.db.Where("(run = ? OR email = ?) AND role = ?", run, email, roleNormalized).
            First(&existingUser).Error

    if err == nil {
        // ENCONTRÓ: Existe ya un usuario con este (Email o RUT) Y este rol específico
        return fmt.Errorf("ya existe una cuenta de %s registrada con este Email o RUT", roleNormalized)
    }
    // Si no lo encuentra, procedemos (puede tener el mismo Email/RUT si rol es diferente)

    // ... resto del flujo
}
```

**Lógica**:

- Si intenta registrar Email=juan@mail.com, Role=adopter y YA EXISTE un adopter con ese email → Rechaza
- Si intenta registrar Email=juan@mail.com, Role=rescuer y NO EXISTE rescatista con ese email (pero SÍ existe adopter) → PERMITE
- Resultado: Un usuario puede ser Adoptante Y Rescatista con los mismos Email/RUT

### Cambios en AuthService para Soportar Doble Identidad

**Nueva función: SwitchRole()**

```go
func (s *AuthService) SwitchRole(currentUserID uint) (string, *domain.User, error) {
    // 1. Obtener usuario actual (su RUT y rol)
    var currentUser domain.User
    if err := s.db.First(&currentUser, currentUserID).Error; err != nil {
        return "", nil, errors.New("usuario no encontrado")
    }

    // 2. Determinar rol objetivo (opuesto)
    targetRole := "rescuer"
    if currentUser.Role == "rescuer" {
        targetRole = "adopter"
    }

    // 3. Buscar el "gemelo" (mismo RUT, rol objetivo)
    var targetUser domain.User
    if err := s.db.Where("run = ? AND role = ?", currentUser.Run, targetRole).
            First(&targetUser).Error; err != nil {
        // No encontrado: Usuario aún no ha creado el otro perfil
        return "", nil, errors.New("no existe un perfil asociado para el modo " + targetRole)
    }

    // 4. Generar JWT para la nueva identidad (SIN pedir contraseña)
    token, err := s.GenerateTokenForUser(&targetUser)
    if err != nil {
        return "", nil, err
    }

    return token, &targetUser, nil
}
```

**Uso**: Un usuario Adoptante presiona "Cambiar a Rescatista" → SwitchRole() busca usuario con (run=adopter.run, role=rescuer) → Genera JWT → Frontend navega a MainLayout del nuevo rol

### Impacto en Validación de Login

La función `Login()` NO se modifica, mantiene su comportamiento de "tomar el primero que encuentra":

```go
func (s *AuthService) Login(email, password string) (string, error) {
    var user domain.User
    if err := s.db.Where("email = ?", email).First(&user).Error; err != nil {
        return "", errors.New("credenciales inválidas")
    }

    if user.IsBanned { return "", errors.New("cuenta suspendida") }

    if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password)); err != nil {
        return "", errors.New("credenciales inválidas")
    }

    return s.GenerateTokenForUser(&user)
}
```

**Nota**: Login retorna un rol (el primero encontrado para ese email). SwitchRole() permite cambiar sin re-login.

### Endpoint HTTP - SwitchRole

Nuevo endpoint en `internal/transport/http/auth_handler.go`:

```go
func (h *AuthHandler) SwitchRole(c *gin.Context) {
    userIDVal, exists := c.Get("userID")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
        return
    }

    var userID uint
    if val, ok := userIDVal.(float64); ok {
        userID = uint(val)
    } else {
        userID = userIDVal.(uint)
    }

    newToken, newUser, err := h.service.SwitchRole(userID)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "message": "Cambio de perfil exitoso",
        "token":   newToken,
        "user":    newUser,
    })
}
```

**Endpoint**: `POST /api/v1/auth/switch-role`  
**Requiere**: JWT válido (extrae userID del middleware)  
**Respuesta**: 200 OK con nuevo token + datos usuario  
**Error**: 404 si no existe cuenta del rol opuesto

### Tabla Comparativa: Etapa 1 vs. Etapa 19

| Aspecto                    | Fase 1 (Original)          | Etapa 19 (Actualizado)                  |
| -------------------------- | -------------------------- | --------------------------------------- |
| **UNIQUE(run)**            | Global (bloquea doble rol) | Compuesto: (run, role)                  |
| **UNIQUE(email)**          | Global (bloquea doble rol) | Compuesto: (email, role)                |
| **Cambio de Rol**          | No existe                  | SwitchRole() endpoint                   |
| **Limpieza de BD**         | Manual                     | Automática (dropLegacyConstraints)      |
| **Validación en Registro** | Valida por rol global      | Valida por (email/run, role) específico |
| **Flexibilidad**           | Usuario = 1 rol            | Usuario = 2 roles máximo                |

### Garantías de Seguridad Preservadas

La doble identidad NO debilita las garantías de Fase 1:

1. **R-SEC-01 (Verificación de Identidad)**: Aún presente en IsVerified (OCR mock en Fase 8)
2. **R-SEC-02 (Prevención de Multicuentas)**: Sigue validando Blacklist y RUT, ahora por (RUT, role)
3. **R-SEC-03 (Blacklist Global)**: Misma tabla, sigue siendo global por RUT (un RUT baneado no puede tener ningún rol)
4. **JWT**: Sigue siendo seguro, generado con rol específico

---

## Referencias

- JWT.io: https://jwt.io
- GORM Docs: https://gorm.io
- Gin Docs: https://gin-gonic.com
- Bcrypt Explanation: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- Clean Architecture: https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html
