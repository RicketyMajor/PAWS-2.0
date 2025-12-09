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
DB_HOST=db
DB_USER=paws_user
DB_PASSWORD=paws_secret_password
DB_NAME=paws_db
DB_PORT=5432
DB_SSL_MODE=disable
PORT=8080
```

### 3. Iniciar Infraestructura (Docker)

```bash
docker-compose up -d
```

Esto levanta:

- PostgreSQL 15 + PostGIS en puerto 5433
- Redis en puerto 6379
- pgAdmin en puerto 5050

Verificar estado:

```bash
docker-compose ps
```

### 4. Ejecutar el Servidor

```bash
go run ./cmd/api/main.go
```

Esperado:

```
✅ Conexión a Base de Datos exitosa
🚀 Servidor PAWS corriendo en el puerto 8080
```

## Acceso a Servicios

| Servicio   | URL                   | Credenciales                     |
| ---------- | --------------------- | -------------------------------- |
| pgAdmin    | http://localhost:5050 | admin@paws.com / admin           |
| PostgreSQL | localhost:5433        | paws_user / paws_secret_password |
| Redis CLI  | redis-cli -p 6379     | -                                |

## Estructura del Proyecto

Para documentación exhaustiva sobre la arquitectura, stack tecnológico y decisiones de diseño, consultar `documentation/Fase-0.md`.

```
PAWS-2.0/
├── cmd/api/                 # Punto de entrada de la aplicación
├── internal/platform/       # Infraestructura y servicios
├── documentation/           # Documentación por fase
├── docker-compose.yml       # Orquestación de servicios
├── go.mod                   # Dependencias de Go
└── README.md               # Este archivo
```

## Detener Servicios

```bash
docker-compose down
```

Para eliminar también los volúmenes de datos:

```bash
docker-compose down -v
```

## Plan de Desarrollo

Este proyecto se desarrolla en fases:

- **Fase 0** (Completada): Infraestructura y estructura del proyecto
- **Fase 1**: Autenticación y seguridad
- **Fase 2**: Gestión de mascotas y perfiles
- **Fase 3**: Matchmaking y geolocalización
- **Fase 4**: Chat en tiempo real distribuido
- **Fase 5**: Frontend con Flutter
- **Fase 6**: Despliegue y orquestación

Consultar `documentation/` para detalles de cada fase.

## Documentación Adicional

- `documentation/Fase-0.md`: Documentación técnica detallada de la infraestructura y cimientos
- Plan de desarrollo completo: Disponible en `documentation/`

## Autor

[Tu nombre o equipo]

## Licencia

[Tu licencia preferida]
