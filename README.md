# PAWS - Pet Adoption Matching System

PAWS es una plataforma de matchmaking diseñada para facilitar adopciones seguras y efectivas entre adoptantes y rescatistas. La aplicación prioriza la seguridad como componente crítico en cada capa.

## Descripción General

PAWS conecta a personas que desean adoptar mascotas con organizaciones y rescatistas que ofrecen animales en adopción. Utiliza geolocalización, algoritmos de matching y comunicación segura en tiempo real para crear una experiencia confiable.

**Stack**: Go (Backend) + Flutter (Frontend) + PostgreSQL + Redis

## Requisitos Previos

- Docker y Docker Compose instalados
- Go 1.18 o superior
- Git

## Instalación y Ejecución

### 1. Clonar el Repositorio

```bash
git clone https://github.com/RicketyMajor/PAWS-2.0.git
cd PAWS-2.0
```

### 2. Crear Archivo .env

En la raíz del proyecto, crear un archivo `.env` con las siguientes variables:

```
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

### 3. Iniciar Infraestructura (Docker)

```bash
docker compose up -d
```

Esto levanta:

- PostgreSQL 15 + PostGIS en puerto 5433
- Redis en puerto 6379
- pgAdmin en puerto 5050

Verificar estado:

```bash
docker compose ps
```

### 4. Ejecutar el Servidor

```bash
go run ./cmd/api/main.go
```

Esperado:

```
 Conexión a Base de Datos exitosa
 Migración de base de datos completada
 Servidor PAWS corriendo en puerto 8080
```

## Pruebas Rápidas de Endpoints

### Registrarse

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

Respuesta exitosa:

```json
{
  "message": "Usuario registrado exitosamente",
  "user_id": 1
}
```

### Iniciar Sesión

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "juan@example.com",
    "password": "securepassword123"
  }'
```

Respuesta exitosa:

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### Crear Mascota (Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/pets \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Max",
    "type": "Dog",
    "breed": "Golden Retriever",
    "age": 24,
    "latitude": -33.5,
    "longitude": -70.5,
    "description": "Perro amigable y energético"
  }'
```

Respuesta exitosa (201):

```json
{
  "id": 1,
  "name": "Max",
  "type": "Dog",
  "status": "available",
  "user_id": 1,
  "created_at": "2025-12-09T10:30:00Z"
}
```

### Obtener Lista de Mascotas (Sin Autenticación)

```bash
curl -X GET http://localhost:8080/api/v1/pets
```

Respuesta exitosa (200):

```json
[
  {
    "id": 1,
    "name": "Max",
    "type": "Dog",
    "breed": "Golden Retriever",
    "status": "available",
    "latitude": -33.5,
    "longitude": -70.5
  }
]
```

### Subir Imagen (Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@dog.jpg"
```

Respuesta exitosa (200):

```json
{
  "url": "/uploads/a0eebc99-9c0b-4ef8-a6b0-6e3d3f5e9c8f.jpg",
  "message": "imagen subida exitosamente"
}
```

### Verificar Identidad (Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/verification/verify \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "document_image_url": "/uploads/a0eebc99-9c0b-4ef8-a6b0-6e3d3f5e9c8f.jpg"
  }'
```

Respuesta exitosa (200):

```json
{
  "message": "Identidad verificada exitosamente. Ahora tienes acceso total.",
  "status": "verified"
}
```

### Buscar Mascotas con Filtros Avanzados (Sin Autenticación)

```bash
curl -X GET "http://localhost:8080/api/v1/pets/search?type=Dog&breed=Golden&lat=-33.5&long=-70.5&radius=10"
```

Respuesta exitosa (200):

```json
[
  {
    "id": 1,
    "name": "Max",
    "type": "Dog",
    "breed": "Golden Retriever",
    "age": 24,
    "status": "available",
    "latitude": -33.5,
    "longitude": -70.5,
    "description": "Perro amigable y energético"
  },
  {
    "id": 3,
    "name": "Luna",
    "type": "Dog",
    "breed": "Golden Doodle",
    "age": 36,
    "status": "available",
    "latitude": -33.48,
    "longitude": -70.52,
    "description": "Juguetona y activa"
  }
]
```

**Parámetros de búsqueda**:

- `type`: Tipo de mascota (Dog, Cat, etc.)
- `breed`: Raza (búsqueda parcial, case-insensitive)
- `lat`: Latitud de ubicación
- `long`: Longitud de ubicación
- `radius`: Radio en kilómetros
- `max_age`: Edad máxima en meses

### Conectar a Chat en Tiempo Real (Requiere Autenticación)

Fase 4 implementa WebSocket para chat distribuido con Redis Pub/Sub.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Conectar cliente WebSocket (ejemplo con wscat)
wscat -c "ws://localhost:8080/api/v1/chat/ws" \
  -H "Authorization: Bearer $TOKEN"
```

Esperado:

```
Connected (press CTRL+C to quit)
> {"message": "Hola"}
< {"message": "Hola"}
< {"user": "user_1", "message": "Hola"}
```

**Características WebSocket Fase 4**:

- Conexión persistente bidireccional
- Distribuido con Redis Pub/Sub (múltiples servidores)
- Filtro de contenido R-SEC-05 (malas palabras)
- Heartbeat ping/pong
- Escalable a miles de conexiones simultáneas

### Obtener Matches de Mascotas (Sin Autenticación)

```bash
curl -X GET "http://localhost:8080/api/v1/pets/match?type=Dog&breed=Golden&max_age=60"
```

Respuesta exitosa (200):

```json
{
  "matches_found": 2,
  "results": [
    {
      "pet": {
        "id": 1,
        "name": "Max",
        "type": "Dog",
        "breed": "Golden Retriever",
        "age": 24,
        "status": "available"
      },
      "match_score": 80
    },
    {
      "pet": {
        "id": 3,
        "name": "Luna",
        "type": "Dog",
        "breed": "Golden Doodle",
        "age": 36,
        "status": "available"
      },
      "match_score": 60
    }
  ]
}
```

**Score de matching** (0-100):

- Tipo correcto: +40 puntos
- Raza coincide: +20 puntos
- Edad aceptable: +20 puntos
- Ubicación disponible: +20 puntos

## Acceso a Servicios

| Servicio   | URL                   | Credenciales                     |
| ---------- | --------------------- | -------------------------------- |
| pgAdmin    | http://localhost:5050 | admin@paws.com / admin           |
| PostgreSQL | localhost:5433        | paws_user / paws_secret_password |
| Redis CLI  | redis-cli -p 6379     | -                                |

## Estructura del Proyecto

Consultar `documentation/` para documentación exhaustiva:

- `Fase-0.md`: Infraestructura, Docker, configuración de base de datos
- `Fase-1.md`: Autenticación, seguridad, JWT y Bcrypt
- `Fase-2.md`: Gestión de mascotas, uploads, middleware, OCR mock
- `Fase-3.md`: Matchmaking, geolocalización avanzada, búsqueda con filtros
- `Fase-4.md`: Chat distribuido, WebSocket, Redis Pub/Sub, seguridad R-SEC-05
- Próximas fases: Flutter frontend, Kubernetes

Estructura actual:

```
PAWS-2.0/
├── cmd/
│   └── api/                 # Punto de entrada de la aplicación
├── internal/
│   ├── core/
│   │   ├── domain/          # Modelos (User, BlacklistEntry, Pet)
│   │   └── services/        # Lógica de negocio
│   │       ├── auth_service.go
│   │       ├── pet_service.go
│   │       ├── match_service.go       # (Fase 3)
│   │       ├── file_service.go
│   │       └── identity_service.go
│   ├── transport/
│   │   ├── http/            # Handlers y middleware HTTP
│   │   │   ├── auth_handler.go
│   │   │   ├── pet_handler.go
│   │   │   ├── match_handler.go       # (Fase 3)
│   │   │   ├── upload_handler.go
│   │   │   ├── identity_handler.go
│   │   │   ├── ws_handler.go          # (Fase 4 - Upgrade WebSocket)
│   │   │   └── middleware/
│   │   │       └── auth.go
│   │   └── websocket/                 # (Fase 4 - Lógica WebSocket)
│   │       ├── client.go              # Cliente WebSocket individual
│   │       └── hub.go                 # Hub distribuido con Redis
│   └── platform/
│       └── database/        # Conexión y migraciones de BD
├── uploads/                 # Almacenamiento local de imágenes
├── documentation/           # Documentación por fase
├── docker-compose.yml       # Orquestación de servicios
├── go.mod                   # Dependencias de Go
├── go.sum                   # Lock de dependencias
├── .env                     # Variables de entorno
└── README.md               # Este archivo
```

## Detener Servicios

```bash
docker compose down
```

Para eliminar también los volúmenes de datos:

```bash
docker compose down -v
```

## Plan de Desarrollo

Este proyecto se desarrolla en fases:

- **Fase 0** (Completada): Infraestructura, Docker, estructura de proyecto
- **Fase 1** (Completada): Autenticación JWT, hashing de contraseñas, blacklist
- **Fase 2** (Completada): Gestión de mascotas, uploads, middleware de auth, OCR mock
- **Fase 3** (Completada): Matchmaking y geolocalización avanzada, búsqueda SQL con filtros
- **Fase 4** (Completada): Chat distribuido con WebSocket, Redis Pub/Sub, seguridad R-SEC-05
- **Fase 5**: Frontend con Flutter
- **Fase 6**: Despliegue y orquestación (Kubernetes)

## Documentación Adicional

- [Fase 0](documentation/Fase-0.md): Infraestructura, Docker, estructura base
- [Fase 1](documentation/Fase-1.md): Autenticación, seguridad, JWT y Bcrypt
- [Fase 2](documentation/Fase-2.md): Gestión de mascotas, uploads, middleware, OCR
- [Fase 3](documentation/Fase-3.md): Matchmaking, geolocalización, búsqueda SQL
- [Fase 4](documentation/Fase-4.md): Chat distribuido, WebSocket, Redis, seguridad real-time

## Autor
