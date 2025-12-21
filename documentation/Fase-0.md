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

## Referencias y Documentación

- Go Standard Project Layout: https://github.com/golang-standards/project-layout
- GORM Documentación: https://gorm.io
- PostGIS Documentation: https://postgis.net/documentation/
- Docker Compose: https://docs.docker.com/compose/
- Redis: https://redis.io/documentation
