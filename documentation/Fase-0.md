# Fase 0: Cimientos e Infraestructura Local

## Introducción

La Fase 0 de PAWS representa el establecimiento de los cimientos del proyecto: la estructura del código, la infraestructura necesaria para el desarrollo local y la conexión inicial a la base de datos. Este documento detalla exhaustivamente qué se ha implementado, cómo funciona y la arquitectura técnica subyacente.

PAWS es una aplicación de matchmaking diseñada para facilitar adopciones seguras y efectivas entre adoptantes y rescatistas (personas y organizaciones que ofrecen mascotas en adopción). La seguridad es un componente crítico en cada capa de la aplicación.

## Objetivos de la Fase 0

Establecer las bases sólidas para el desarrollo posterior mediante:

1. Estructura de carpetas siguiendo estándares de Go moderno
2. Configuración del módulo Go y sus dependencias
3. Infraestructura local con Docker Compose (PostgreSQL, Redis, pgAdmin)
4. Conexión funcional a la base de datos PostgreSQL
5. Configuración de variables de entorno para desarrollo

## Stack Tecnológico

### Backend

- **Lenguaje**: Go 1.18+
- **ORM**: GORM v1.31.1
- **Driver de Base de Datos**: pgx v5 (a través de GORM)
- **Carga de Variables de Entorno**: godotenv v1.5.1

### Base de Datos

- **PostgreSQL**: Versión 15 con extensión PostGIS 3.3
- **PostGIS**: Extensión para funcionalidades geoespaciales (necesaria para buscar mascotas en un radio específico)
- **Redis**: Caché y pub/sub para chat distribuido y validación rápida de blacklist

### Infraestructura

- **Docker Compose**: Orquestación de servicios locales
- **pgAdmin**: Interfaz gráfica para gestionar la base de datos
- **Red Docker**: Todos los servicios conectados en una red interna llamada `paws_network`

## Estructura del Proyecto

```
PAWS-2.0/
├── cmd/
│   └── api/
│       └── main.go                 # Punto de entrada de la aplicación
├── internal/
│   └── platform/
│       └── database/
│           └── postgres.go         # Configuración y conexión a PostgreSQL
├── documentation/
│   ├── Fase-0.md                   # Este archivo
│   └── [futuras fases]
├── docker-compose.yml              # Orquestación de servicios Docker
├── go.mod                          # Definición del módulo Go y dependencias
├── README.md                       # Guía rápida de inicio
└── [archivos futuros]
```

### Explicación Detallada de Carpetas

#### `/cmd/api/`

Contiene el punto de entrada principal de la aplicación. Siguiendo el estándar de Go, cada comando ejecutable va en su propia subcarpeta dentro de `cmd`. En este caso, `api` es el único comando por ahora, pero en el futuro podrían existir otros (por ejemplo, `cmd/migration` para herramientas de base de datos).

**Archivo**: `main.go`

- Responsable de cargar las variables de entorno
- Inicializar la conexión a la base de datos
- Mantener el servidor ejecutándose

#### `/internal/platform/`

Contiene el código "privado" de la aplicación que no se exporta a otros paquetes. La carpeta `platform` agrupa toda la infraestructura y servicios transversales.

**Subcarpeta**: `/database/`

- Gestiona toda la configuración y conexión a PostgreSQL
- Implementa la lógica de inicialización de la conexión
- Exporta una variable global `DB` que será utilizada por toda la aplicación (en futuras refactorizaciones, esto pasará por inyección de dependencias)

#### `/documentation/`

Almacena toda la documentación del proyecto, organizada por fase de desarrollo.

## Detalles Técnicos Implementados

### 1. Módulo Go (go.mod)

```
module github.com/RicketyMajor/PAWS-2.0
go 1.18
```

Define que este es un módulo Go llamado `PAWS-2.0`, lo cual permite que otros proyectos lo importen si es público. Las importaciones en el código usan la ruta completa:

```go
import "github.com/RicketyMajor/PAWS-2.0/internal/platform/database"
```

#### Dependencias Principales

| Dependencia       | Versión | Propósito                                             |
| ----------------- | ------- | ----------------------------------------------------- |
| `godotenv`        | v1.5.1  | Carga archivos `.env` para variables de entorno       |
| `gorm`            | v1.31.1 | ORM para abstracción de base de datos                 |
| `driver/postgres` | v1.6.0  | Driver específico de GORM para PostgreSQL             |
| `pgx`             | v5.6.0  | Driver de bajo nivel para PostgreSQL (usado por GORM) |

Las otras dependencias son transitorias (requieren de las anteriores).

### 2. Docker Compose (docker-compose.yml)

Levanta tres servicios en una red privada Docker llamada `paws_network`:

#### Servicio PostgreSQL

```yaml
db:
  image: postgis/postgis:15-3.3
  container_name: paws_db
  environment:
    POSTGRES_USER: paws_user
    POSTGRES_PASSWORD: paws_secret_password
    POSTGRES_DB: paws_db
  ports:
    - "5433:5432"
  volumes:
    - postgres_data:/var/lib/postgresql/data
```

**Características**:

- Imagen: PostGIS 15-3.3 (PostgreSQL 15 + extensión espacial)
- Puerto local: 5433 (para evitar conflictos si hay otro PostgreSQL)
- Credenciales: Usuario `paws_user`, contraseña `paws_secret_password`, BD `paws_db`
- Volumen persistente: Los datos se guardan en `postgres_data` y persisten entre reinicios
- Red: Accesible internamente como `db` (hostname dentro de Docker)

**Por qué PostGIS**:
En la Fase 3 se implementará búsqueda geoespacial (e.g., "mascotas dentro de 5km"). PostGIS proporciona tipos de datos (POINT, POLYGON) y funciones SQL especializadas para esto.

#### Servicio Redis

```yaml
redis:
  image: redis:alpine
  container_name: paws_redis
  ports:
    - "6379:6379"
  volumes:
    - redis_data:/data
```

**Características**:

- Imagen Alpine (muy ligera)
- Propósito dual:
  1. **Caché**: Almacenar datos frecuentes (e.g., blacklist de usuarios maliciosos) para acceso instantáneo
  2. **Pub/Sub**: Canal de mensajes para el chat distribuido en la Fase 4

#### Servicio pgAdmin

```yaml
pgadmin:
  image: dpage/pgadmin4
  environment:
    PGADMIN_DEFAULT_EMAIL: admin@paws.com
    PGADMIN_DEFAULT_PASSWORD: admin
  ports:
    - "5050:80"
```

**Propósito**: Interfaz gráfica web para administrar PostgreSQL sin necesidad de instalar herramientas externas.

- Acceso: http://localhost:5050
- Credenciales: admin@paws.com / admin

### 3. Punto de Entrada (cmd/api/main.go)

```go
func main() {
	if err := godotenv.Load(); err != nil {
		log.Fatal("Error cargando el archivo .env")
	}

	database.Connect()

	port := os.Getenv("PORT")
	log.Printf("[START] Servidor PAWS corriendo en el puerto %s", port)
}
```

**Flujo de Ejecución**:

1. **Cargar `.env`**: Lee el archivo `.env` en la raíz del proyecto y establece variables de entorno
2. **Conectar a BD**: Llama a `database.Connect()` que valida y abre la conexión con PostgreSQL
3. **Imprimir estado**: Confirma que el servidor está iniciado

**Notas Arquitectónicas**:

- La carga de `.env` es lo primero porque todo lo demás depende de esas variables
- Si la conexión a BD falla, el programa se detiene inmediatamente (comportamiento deseable en desarrollo)
- En futuras fases, aquí irá la inicialización del servidor HTTP, rutas, middleware, etc.

### 4. Configuración de Base de Datos (internal/platform/database/postgres.go)

```go
var DB *gorm.DB

func Connect() {
	host := os.Getenv("DB_HOST")
	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")
	port := os.Getenv("DB_PORT")
	sslMode := os.Getenv("DB_SSL_MODE")

	dsn := fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=%s",
		host, user, password, dbName, port, sslMode)

	connection, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal("[ERROR] Error conectando a la base de datos: ", err)
	}

	DB = connection
	log.Println("[SUCCESS] Conexión a Base de Datos exitosa")
}
```

#### Explicación Detallada

**DSN (Data Source Name)**:
La cadena de conexión es la "dirección" de la base de datos. Ejemplo real:

```
host=db user=paws_user password=paws_secret_password dbname=paws_db port=5432 sslmode=disable
```

- `host=db`: Nombre del servicio Docker (Docker resuelve automáticamente esto a la IP del contenedor)
- `port=5432`: Puerto interno del contenedor (no el 5433 expuesto localmente)
- `sslmode=disable`: Para desarrollo local (en producción usaríamos `require`)

**Variable Global `DB`**:
Por simplicidad en la Fase 0, la conexión se guarda como variable global. En futuras refactorizaciones (Fase 2 o 3), se pasará como inyección de dependencias a través de interfaces.

Ejemplo de cómo se usaría en el resto del código:

```go
var users []User
database.DB.Find(&users) // Buscar todos los usuarios
```

## Variables de Entorno Requeridas

El archivo `.env` debe contener:

```
# Base de Datos
DB_HOST=db                          # Nombre del servicio Docker
DB_USER=paws_user                   # Usuario PostgreSQL
DB_PASSWORD=paws_secret_password    # Contraseña PostgreSQL
DB_NAME=paws_db                     # Nombre de la base de datos
DB_PORT=5432                        # Puerto interno del contenedor
DB_SSL_MODE=disable                 # Para desarrollo local

# Servidor
PORT=8080                           # Puerto donde escucha el servidor
```

## Flujo de Inicialización Completo

```
1. docker-compose up -d
   └─> PostgreSQL inicia en puerto 5433
   └─> Redis inicia en puerto 6379
   └─> pgAdmin inicia en puerto 5050

2. go run ./cmd/api/main.go
   └─> Carga variables de .env
   └─> Conecta a PostgreSQL mediante GORM
   └─> Confirma conexión exitosa
   └─> Servidor listo (aunque sin rutas HTTP aún)
```

## Decisiones Arquitectónicas

### 1. Uso de GORM en lugar de SQL puro

**Razón**:

- Abstracción de base de datos (facilita cambios futuros)
- Migrations automáticas
- Type-safe queries
- Validación de modelos integrada

### 2. Separación cmd/internal

Siguiendo convenciones de Go:

- `cmd/`: Código ejecutable
- `internal/`: Código privado no exportable
- `pkg/`: (futuro) Código reutilizable que podría exportarse

### 3. Variable Global DB

**Limitación actual**: La variable global `DB` en `database.go` es una solución temporal aceptable en la Fase 0 para acelerar desarrollo.

**Plan de refactorización (Fase 1-2)**:

```go
type Handler struct {
    db *gorm.DB
}

func NewHandler(db *gorm.DB) *Handler {
    return &Handler{db: db}
}

func (h *Handler) CreateUser(w http.ResponseWriter, r *http.Request) {
    h.db.Create(&user)
}
```

Esto permitiría:

- Testing unitario más fácil (mock de DB)
- Múltiples conexiones si es necesario
- Mayor claridad sobre dependencias

### 4. PostGIS en lugar de PostgreSQL vanilla

**Razón**:
La Fase 3 requiere búsquedas geoespaciales. Usar PostGIS desde el inicio evita migración de datos problemática después.

**Funcionalidades futuras**:

```sql
SELECT pet_id, pet_name FROM pets
WHERE ST_DWithin(
    location::geography,
    ST_Point(-70.5, -33.5)::geography,
    5000  -- 5km en metros
);
```

### 5. Redis para Blacklist y Chat

**Blacklist (Fase 1)**:

- Caché en Redis de usuarios bloqueados
- Consulta instantánea antes de cualquier operación sensible
- Invalidación automática cuando se actualiza

**Chat (Fase 4)**:

- Redis Pub/Sub permite que múltiples instancias del servidor se comuniquen
- Si existe Servidor A y B, ambos se conectan al mismo Redis
- Usuario en Servidor A puede chatear con usuario en Servidor B


## Actualización Etapa 1: Kill Switch de RabbitMQ (Asincronía Condicional)

La Etapa 1 de Operación PAWS Real introduce un mecanismo crítico de "Kill Switch" que permite que el sistema funcione sin RabbitMQ, una dependencia pesada no adecuada para desarrollo local rápido.

### Problema de Infraestructura

El envío de emails (especialmente códigos OTP) requería integración con RabbitMQ para:
- Desacoplar el servicio de autenticación de la tarea de envío de email
- Permitir reintentos automáticos si el servicio de email falla
- Escalar el envío de notificaciones en producción

Sin embargo, esto creaba un obstáculo para desarrolladores locales:
- Instalación y configuración de RabbitMQ es pesada
- Requiere conocimiento de colas y pub/sub
- Ralentiza el ciclo de desarrollo (iniciar múltiples servicios)
- No todos los desarrolladores tienen acceso a infraestructura completa

### Solución: Kill Switch con ENABLE_ASYNC_FEATURES

Se implementó un patrón de "Kill Switch" que permite alternar entre modo asincrónico (con RabbitMQ) y sincrónico (con logging a consola).

#### Variable de Entorno

```bash
# En .env o variables del sistema
ENABLE_ASYNC_FEATURES=true    # Activa RabbitMQ y procesamiento async
ENABLE_ASYNC_FEATURES=false   # (default) Sincrónico, RabbitMQ opcional
```

#### Implementación en main.go

```go
package main

import (
    "os"
    "log"
    "github.com/joho/godotenv"
    "internal/messaging"
)

func main() {
    godotenv.Load()
    
    // KILL SWITCH: Decidir si usar RabbitMQ
    var mqClient *messaging.RabbitMQClient
    var err error
    
    if os.Getenv("ENABLE_ASYNC_FEATURES") == "true" {
        mqClient, err = messaging.ConnectRabbitMQ(
            "amqp://guest:guest@rabbitmq:5672/",
        )
        if err != nil {
            log.Printf("[WARNING] No se pudo conectar a RabbitMQ: %v", err)
            log.Printf("[INFO] Sistema degradado a modo sincrónico")
            mqClient = nil  // Fallback seguro
        } else {
            log.Println("[INFO] Async Features ACTIVADAS - RabbitMQ conectado")
        }
    } else {
        log.Println("[INFO] Async Features DESACTIVADAS - Modo sincrónico")
    }
    
    // Inyectar mqClient (puede ser nil) en servicios
    otpService := services.NewOTPService(mqClient)
    authHandler := handlers.NewAuthHandler(otpService)
    
    r := gin.Default()
    // ... resto de configuración
}
```

#### Flujo por Modo

**Modo Asincrónico (ENABLE_ASYNC_FEATURES=true)**:
```
Usuario registra → AuthHandler.Register()
    → OTPService.GenerateOTP()
    → Publica a RabbitMQ queue "email_notifications"
    → Responde inmediatamente al usuario
    → Worker externo consume queue y envía email
```

**Modo Sincrónico (default)**:
```
Usuario registra → AuthHandler.Register()
    → OTPService.GenerateOTP()
    → mqClient es nil → Loguea a consola [DEV MODE]
    → Responde inmediatamente al usuario
    → En logs aparece el código OTP para testing
```

### OTPService Manejo de Fallback

```go
// internal/core/services/otp_service.go

type OTPService struct {
    mqClient *messaging.RabbitMQClient  // Puede ser nil
}

func NewOTPService(mq *messaging.RabbitMQClient) *OTPService {
    return &OTPService{mqClient: mq}
}

func (s *OTPService) GenerateOTP(email string) (string, error) {
    code := s.generateRandomCode(6)  // "123456"
    
    if s.mqClient != nil {
        // Modo async: Publicar a cola
        err := s.mqClient.Publish("email_notifications", OTPEvent{
            Email: email,
            Code:  code,
        })
        if err != nil {
            // Fallback si falla publish
            log.Printf("[FALLBACK] No se pudo publicar a RabbitMQ: %v. Logeando.", err)
            log.Printf("[DEV MODE] OTP para %s: %s", email, code)
        }
    } else {
        // Modo sync: Loguear directamente
        log.Printf("[DEV MODE] OTP generado para %s: %s", email, code)
    }
    
    return code, nil
}
```

### Configuración de docker-compose.yml

La configuración de docker-compose.yml deliberadamente **NO incluye RabbitMQ**:

```yaml
version: '3.8'

services:
  db:
    image: postgis/postgis:15-3.3
    # ...
  
  redis:
    image: redis:alpine
    # ...
  
  backend:
    build: .
    environment:
      ENABLE_ASYNC_FEATURES: "false"  # Explícitamente desactivado
    ports:
      - "8080:8080"
    # ... NO incluye RabbitMQ

volumes:
  postgres_data:
  redis_data:
```

**Razón**: Los desarrolladores pueden iniciar `docker-compose up` y tener un sistema completamente funcional sin dependencias extra.

### Ventajas del Kill Switch

1. **Desarrollo Rápido**: `docker-compose up` → sistema listo en 10 segundos
2. **Graceful Degradation**: Si RabbitMQ falla, sistema sigue funcionando
3. **Testing Fácil**: En modo sincrónico, codes aparecen en logs
4. **Escalabilidad**: En producción, `ENABLE_ASYNC_FEATURES=true` + RabbitMQ = full async
5. **Flexibilidad Arquitectónica**: Cambiar de sync a async sin recompilación

### Casos de Uso

#### Caso 1: Desarrollo Local (Default)

```bash
cd PAWS-2.0
docker-compose up                    # RabbitMQ no necesario
# Backend accesible en http://localhost:8080
# OTP codes aparecen en logs de backend
```

#### Caso 2: Testing con Async

```bash
# Instalar RabbitMQ localmente
docker run -d --name rabbitmq -p 5672:5672 rabbitmq:3.12

# Activar async
ENABLE_ASYNC_FEATURES=true docker-compose up

# Backend intenta conectar a RabbitMQ y procesa async
```

#### Caso 3: Producción

```bash
# En servidor de producción
ENABLE_ASYNC_FEATURES=true
RABBITMQ_URL=amqp://user:pass@rabbitmq-prod:5672/

# Ejecutar con email worker + notifications processor
# Sistema completamente asincrónico y escalable
```

### Testing de Kill Switch

Para verificar que el Kill Switch funciona:

```bash
# Verificar modo sincrónico (default)
docker-compose up
# En logs deberías ver:
# [INFO] Async Features DESACTIVADAS - Modo sincrónico

# Registrar usuario:
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com", "password":"pass123", "role":"adopter"}'

# En logs del backend aparecerá:
# [DEV MODE] OTP generado para user@example.com: 456789
```

### Salidas hacia Etapa 2

- **Identidad y Perfiles**: OTP completamente validado y listo para verificación de email
- **Rescatista Dashboard**: Backend puede escalar a async en producción sin cambios de código
- **Chat Real-time**: Redis ya está disponible para pub/sub
- **Producción**: Infraestructura preparada para full async con RabbitMQ

## Referencias y Documentación

- Go Standard Project Layout: https://github.com/golang-standards/project-layout
- GORM Documentación: https://gorm.io
- PostGIS Documentation: https://postgis.net/documentation/
- Docker Compose: https://docs.docker.com/compose/
- Redis: https://redis.io/documentation
