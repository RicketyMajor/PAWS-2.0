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
✅ Conexión a Base de Datos exitosa
✅ Migración de base de datos completada
🚀 Servidor PAWS corriendo en puerto 8080
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

## Acceso a Servicios

| Servicio   | URL                   | Credenciales                     |
| ---------- | --------------------- | -------------------------------- |
| pgAdmin    | http://localhost:5050 | admin@paws.com / admin           |
| PostgreSQL | localhost:5433        | paws_user / paws_secret_password |
| Redis CLI  | redis-cli -p 6379     | -                                |

## Estructura del Proyecto

Consultar `documentation/` para documentación exhaustiva:

- `Fase-0.md`: Infraestructura, Docker, configuración de base de datos
- `Fase-1.md`: Autenticación, seguridad, modelos de datos
- Próximas fases: Mascotas, matchmaking, chat

Estructura actual:

```
PAWS-2.0/
├── cmd/
│   └── api/                 # Punto de entrada de la aplicación
├── internal/
│   ├── core/
│   │   ├── domain/          # Modelos de datos (User, BlacklistEntry)
│   │   └── services/        # Lógica de negocio (AuthService)
│   ├── transport/
│   │   └── http/            # Handlers HTTP (AuthHandler)
│   └── platform/
│       └── database/        # Conexión y migraciones de BD
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
- **Fase 2**: Gestión de mascotas, perfiles y subida de imágenes
- **Fase 3**: Matchmaking y geolocalización
- **Fase 4**: Chat en tiempo real distribuido con Redis
- **Fase 5**: Frontend con Flutter
- **Fase 6**: Despliegue y orquestación (Kubernetes)

## Documentación Adicional

- [Fase 0](documentation/Fase-0.md): Infraestructura, Docker, estructura base
- [Fase 1](documentation/Fase-1.md): Autenticación, seguridad, JWT y Bcrypt
- Próximas fases: Documentadas en `documentation/`

## Autor
