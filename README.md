# PAWS - Pet Adoption Matching System

PAWS es una plataforma de matchmaking diseñada para facilitar adopciones seguras y efectivas entre adoptantes y rescatistas. La aplicación prioriza la seguridad como componente crítico en cada capa.

## Descripción General

PAWS conecta a personas que desean adoptar mascotas con organizaciones y rescatistas que ofrecen animales en adopción. Utiliza geolocalización, algoritmos de matching y comunicación segura en tiempo real para crear una experiencia confiable.

**Stack**: Go (Backend) + Flutter (Frontend) + PostgreSQL + Redis

**Arquitectura**: Monorepo con separación Backend (cmd/, internal/) y Frontend (app/)

## Características Principales por Fase

### Fase 7: CI/CD y Testing Automático

**Objetivos Logrados**:

- Pipeline CI/CD completamente funcional en GitHub Actions
- Análisis estático automático con golangci-lint (detecta bugs, style issues, code smells)
- Escaneo automático de vulnerabilidades CVE con govulncheck
- Tests unitarios integrados en pipeline (go test -v ./...)
- Docker build & push automático a Docker Hub en cada push a main/develop
- Cobertura de código con reportes HTML

**Beneficios**:

- Código de calidad garantizado antes de merge
- Vulnerabilidades detectadas automáticamente
- Imágenes Docker siempre actualizadas en Docker Hub
- Confianza en que main branch siempre está funcional
- Ahorro de 5+ minutos de testing manual por push

### Fase 8: Seguridad Robusta (Evil PAWS)

**Objetivos Logrados**:

1. **R-SEC-01: Verificación de Identidad**

   - Carga de documento de identidad a MinIO (S3-compatible)
   - Validación automática de RUT chileno con algoritmo Módulo 11
   - Generación de RUT válido con dígito verificador correcto
   - Almacenamiento seguro en la nube

2. **R-SEC-02: Anti-Multicuentas**

   - Chequeo automático de RUN único en registro y login
   - Prevención de múltiples cuentas por usuario
   - Validación en base de datos con UNIQUE constraint

3. **R-SEC-03: Blacklist System**

   - Sistema de blacklist para usuarios baneados
   - Chequeo en Register y Login
   - Prevención de acceso a usuarios baneados

4. **R-SEC-04: Sistema de Reportes con Auto-Ban**
   - Usuarios pueden reportar comportamiento inapropiado
   - Sistema automático: 3 reportes verificados = ban automático
   - Sin intervención manual requerida
   - Integración con blacklist automática

**Servicios Nuevos**:

- `IdentityService`: Gestión de verificación de identidad
- `OTPService`: Generación de códigos OTP 6-dígito con TTL de 5 minutos
- `ReportService`: Sistema de reportes con contador automático
- Modelos: `Report`, `BlacklistEntry`

**Algoritmos Implementados**:

- Módulo 11 para validación de RUT chileno
- Generación de RUT aleatorio válido
- OTP de 6 dígitos con almacenamiento en Redis

### Fase 9: Matchmaking Inteligente y Perfiles Enriquecidos

**Objetivos Logrados**:

1. **Perfiles Enriquecidos (UserProfile)**

   - Información demográfica del adoptante: vivienda (casa/depto/parcela), tiene patio, tiene niños, tiene otras mascotas
   - Experiencia (principiante/intermedio/experto) y tiempo disponible (bajo/medio/alto)
   - Relación 1-a-1 con User (único por usuario adoptante)

2. **Compatibilidad de Mascotas**

   - Extensión de modelo Pet con atributos de compatibilidad
   - Nuevos campos: RequiresYard, GoodWithKids, GoodWithDogs, GoodWithCats, EnergyLevel
   - Hard constraints para filtrado inteligente

3. **Algoritmo Inteligente (GetSwipeDeck)**

   - Filtrado servidor-side de candidatos compatibles
   - Excluyente: Mascota que requiere patio + adoptante en depto = EXCLUIDA
   - Excluyente: Mascota no segura con niños + adoptante con niños = EXCLUIDA
   - Excluyente: Mascota no sociable + adoptante con otras mascotas = EXCLUIDA
   - Exclusión de mascotas ya visitadas por el adoptante

4. **Flujo de Matchmaking**

   - Adopter: Swipe(Like) → Crea Match(status=pending)
   - Rescatista: GetPending() → Ve solicitudes de sus mascotas
   - Rescatista: Respond(Accept/Reject) → Actualiza Match(status=accepted/rejected)
   - Integración con Fase 4 (Chat) una vez aceptado

**Servicios Nuevos**:

- `UserService`: CreateOrUpdateProfile, GetProfile
- `MatchService`: GetSwipeDeck (algoritmo inteligente), Swipe, GetPendingRequests, RespondMatch
- Modelos: `UserProfile`, `Match` con MatchStatus enum

**Características Clave**:

- Motor de compatibilidad real basado en atributos
- Prevención de adopciones incompatibles desde el algoritmo
- Estado Pending como sincronización entre partes
- Preparado para ML/Scoring en futuras fases

## Requisitos Previos

### Backend

- Docker y Docker Compose instalados
- Go 1.24 o superior
- WSL2 (si estás en Windows)
- Git (para clonar el repo)

### Backend Testing y CI/CD (Fase 7)

- Go testing tools (incluido en Go SDK)
- GitHub Actions habilitado en el repositorio
- golangci-lint para análisis estático local (ejecutado automáticamente en CI/CD)
- govulncheck para escaneo de vulnerabilidades (ejecutado automáticamente en CI/CD)
- Docker Hub account (opcional, para push de imágenes)

### Backend Security (Fase 8)

- MinIO S3-compatible storage (incluido en docker-compose)
- Redis para OTP storage (incluido en docker-compose)
- PostgreSQL con soporte para UNIQUE constraints (incluido en docker-compose)

### Frontend

- Flutter SDK 3.24.0 o superior
- Dart 3.10.4 o superior
- Android Studio / VS Code con extensiones Flutter
- Android Emulator o dispositivo físico

### Desarrollo Híbrido (Windows + WSL2)

- Windows 11/10 Pro (WSL2 disponible)
- PowerShell (para ejecutar script netsh)
- Emulador de Android en Hyper-V

### Infraestructura (Fase 6)

- Docker Desktop instalado (proporciona Kubernetes)
- kubectl (cliente de línea de comandos para Kubernetes)
- Kubernetes cluster habilitado en Docker Desktop
- WSL2 configurado para acceder al cluster desde Linux

### General

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

### 4.1 Testing del Backend (Fase 7)

Antes de hacer un PR, asegúrate de que los tests pasen:

```bash
# Ejecutar todos los tests unitarios
go test -v ./...

# Ejecutar tests con cobertura
go test -cover ./...

# Generar reporte HTML de cobertura
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

Esperado:

```
ok      github.com/RicketyMajor/PAWS-2.0/internal/core/services  0.005s
Todos los tests pasaron!
```

**GitHub Actions**: Cuando hagas push, GitHub Actions ejecuta automáticamente los tests. Si algo falla, tu PR quedará en rojo (bloqueado para merge).

### 5. Ejecutar Frontend Flutter (Fase 5)

#### Windows + WSL2 Setup

Si estás en Windows con WSL2 y Android Emulator:

1. Ejecutar el script de puente de red:

```bash
cd app
powershell -ExecutionPolicy Bypass -File conectar_backend.ps1
```

Esto crea un puente netsh que redirige puerto 8080 desde Windows a WSL2.

2. Instalar dependencias Flutter:

```bash
cd app
flutter pub get
```

3. Ejecutar en emulador o dispositivo:

```bash
# Listar dispositivos disponibles
flutter devices

# Ejecutar en emulador
flutter run
```

Esperado: App se abre en emulador, se conecta a backend en WSL2.

### 6. Desplegar con Kubernetes (Fase 6)

#### Opción A: Docker Compose (Local, Simple)

```bash
# Construir e iniciar todos los servicios
docker compose up

# Verificar que está corriendo
docker compose ps

# Acceso:
# - Backend API: localhost:8080
# - MinIO Console: localhost:9001
# - PostgreSQL: localhost:5432
# - Redis: localhost:6379

# Detener
docker compose down
```

#### Opción B: Kubernetes (Local Cluster)

Primero, habilitar Kubernetes en Docker Desktop:

1. Abrir Docker Desktop Preferences
2. Ir a Kubernetes
3. Habilitar "Enable Kubernetes"

Luego, desplegar manifiestos:

```bash
# Construir imagen Docker
docker build -t paws-backend:k8s .

# Aplicar todos los manifiestos K8s
kubectl apply -f k8s/

# Verificar estado de Pods
kubectl get pods
kubectl get services

# Ver logs del Backend
kubectl logs deployment/backend-deployment

# Acceso:
# - Backend API: localhost:8080 (LoadBalancer)
# - MinIO Console: localhost:9001 (LoadBalancer)
# - PostgreSQL: acceso interno solo (ClusterIP)
# - Redis: acceso interno solo (ClusterIP)

# Limpiar
kubectl delete -f k8s/
```

### 7. Ejecutar Frontend Flutter (Fase 5)

Si estás en Linux o Mac:

```bash
cd app
flutter pub get
flutter run
```

## Estrategia de Testing (Fase 7 y 8)

### Unit Tests (Fase 7)

PAWS implementa unit tests para lógica crítica:

```bash
# Ejecutar todos los unit tests
go test -v ./...

# Ejecutar tests de un paquete específico
go test -v ./internal/core/services/

# Ejecutar con cobertura
go test -cover ./...

# Generar reporte HTML de cobertura
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

Esperado:

```
--- PASS: TestCheckBlacklist
--- PASS: TestMathOperations
--- PASS: TestThreeStrikesBan (Fase 8)
ok      github.com/RicketyMajor/PAWS-2.0/internal/core/services  0.050s
```

**Tests Implementados**:

- `auth_service_test.go`: TestCheckBlacklist, TestRegisterDuplicate
- `math_test.go`: TestMathOperations (benchmark)
- `report_service_test.go`: TestThreeStrikesBan (Fase 8 - auto-ban después de 3 reports)

### CI/CD Pipeline Automático (Fase 7)

Cuando hagas `git push` a main/develop, GitHub Actions ejecuta automáticamente:

1. **Quality Gate** (En cada push y PR):

   - golangci-lint: Análisis estático de código (linting)
   - govulncheck: Escaneo de vulnerabilidades CVE conocidas
   - go build: Verifica que el código compile
   - go test: Ejecuta todos los unit tests

2. **Build & Push Docker** (Solo en push a main/develop, no en PR):
   - Construye imagen Docker multi-stage
   - Push a Docker Hub con tag SHA del commit
   - Caché optimizado para builds rápidos

**Archivo Pipeline**: [.github/workflows/ci.yml](.github/workflows/ci.yml)

**Resultado**: PR con estado verde (OK para merge) o rojo (necesita fixes).

### Tests de Seguridad (Fase 8)

Fase 8 implementa verificación de seguridad:

- **R-SEC-01**: Verificación de identidad (documento con MinIO)
- **R-SEC-02**: Anti-multicuentas (único RUN por usuario)
- **R-SEC-03**: Blacklist system (previene acceso de usuarios baneados)
- **R-SEC-04**: Report system con auto-ban (3 reports verificados = ban automático)

Consultar [Fase-8.md](documentation/Fase-8.md) para detalles exhaustivos.

## Pruebas Rápidas de Endpoints (Backend)

Usa cualquiera de estos endpoints dependiendo de cómo ejecutes el backend:

- **Docker Compose**: localhost:8080
- **Kubernetes**: localhost:8080 (LoadBalancer)
- **Desarrollo** (go run): localhost:8080

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

### Actualizar Perfil de Adoptante (Fase 9 - Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X PUT http://localhost:8080/api/v1/profile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "housing": "apartment",
    "has_yard": false,
    "has_children": true,
    "has_other_pets": false,
    "experience": "beginner",
    "time_available": "high"
  }'
```

Respuesta exitosa (200):

```json
{ "message": "Perfil actualizado correctamente" }
```

### Obtener Candidatos Compatibles (Fase 9 - Requiere Autenticación)

Retorna mascotas filtradas según algoritmo inteligente de compatibilidad.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/candidates \
  -H "Authorization: Bearer $TOKEN"
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
    "energy_level": "high",
    "good_with_kids": true,
    "good_with_dogs": true,
    "requires_yard": false,
    "status": "available"
  },
  {
    "id": 5,
    "name": "Luna",
    "type": "Dog",
    "breed": "Labrador",
    "age": 36,
    "energy_level": "medium",
    "good_with_kids": true,
    "good_with_dogs": false,
    "requires_yard": false,
    "status": "available"
  }
]
```

### Dar Like a Mascota (Fase 9 - Requiere Autenticación)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/matches/swipe \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pet_id": 1,
    "is_like": true
  }'
```

Respuesta exitosa (200):

```json
{ "message": "Acción registrada" }
```

### Ver Solicitudes Pendientes (Fase 9 - Requiere Autenticación - Rescatista)

Rescatista ve quién dio Like a sus mascotas.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X GET http://localhost:8080/api/v1/matches/requests \
  -H "Authorization: Bearer $TOKEN"
```

Respuesta exitosa (200):

```json
[
  {
    "id": 42,
    "adopter": {
      "id": 1,
      "name": "Juan Pérez",
      "email": "juan@mail.com"
    },
    "pet": {
      "id": 1,
      "name": "Max",
      "type": "Dog",
      "breed": "Golden Retriever"
    },
    "status": "pending",
    "created_at": "2025-12-22T10:30:00Z"
  }
]
```

### Responder a Solicitud de Match (Fase 9 - Requiere Autenticación - Rescatista)

Rescatista acepta o rechaza solicitud de adopción.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:8080/api/v1/matches/respond \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "match_id": 42,
    "accept": true
  }'
```

Respuesta exitosa (200):

```json
{ "message": "Respuesta registrada" }
```

## Acceso a Servicios

### Docker Compose

| Servicio   | URL                   | Credenciales                     |
| ---------- | --------------------- | -------------------------------- |
| pgAdmin    | http://localhost:5050 | admin@paws.com / admin           |
| PostgreSQL | localhost:5433        | paws_user / paws_secret_password |
| Redis CLI  | redis-cli -p 6379     | -                                |

### Kubernetes

| Servicio   | URL/Acceso                      | Tipo         |
| ---------- | ------------------------------- | ------------ |
| Backend    | localhost:8080                  | LoadBalancer |
| MinIO      | localhost:9001 (console)        | LoadBalancer |
| PostgreSQL | postgres-service:5432 (interno) | ClusterIP    |
| Redis      | redis-service:6379 (interno)    | ClusterIP    |

## Estructura del Proyecto

Consultar `documentation/` para documentación exhaustiva:

- `Fase-0.md`: Infraestructura, Docker, configuración de base de datos
- `Fase-1.md`: Autenticación, seguridad, JWT y Bcrypt
- `Fase-2.md`: Gestión de mascotas, uploads, middleware, OCR mock
- `Fase-3.md`: Matchmaking, geolocalización avanzada, búsqueda con filtros
- `Fase-4.md`: Chat distribuido, WebSocket, Redis Pub/Sub, seguridad R-SEC-05
- `Fase-5.md`: Frontend Flutter, Clean Architecture, BLoC, arquitectura híbrida
- `Fase-6.md`: Dockerización, Kubernetes, orquestación de contenedores
- `Fase-7.md`: CI/CD pipeline, testing unitario, análisis estático, seguridad de dependencias
- `Fase-8.md`: Verificación de identidad, anti-multicuentas, blacklist, auto-ban system

Estructura actual (Monorepo Backend + Frontend):

```
PAWS-2.0/                               # Raíz del monorepo
├── app/                                # Frontend Flutter (FASE 5)
│   ├── lib/
│   │   ├── core/
│   │   │   └── constants/
│   │   │       └── api_constants.dart
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   │   ├── data/
│   │   │   │   │   └── auth_repository.dart
│   │   │   │   └── presentation/
│   │   │   │       ├── bloc/
│   │   │   │       │   └── login_bloc.dart
│   │   │   │       └── screens/
│   │   │   │           ├── login_screen.dart
│   │   │   │           └── register_screen.dart
│   │   │   ├── pets/
│   │   │   │   ├── domain/
│   │   │   │   │   └── pet_model.dart
│   │   │   │   ├── data/
│   │   │   │   │   └── pets_repository.dart
│   │   │   │   └── presentation/
│   │   │   │       ├── bloc/
│   │   │   │       │   └── pets_bloc.dart
│   │   │   │       └── screens/
│   │   │   │           └── feed_screen.dart
│   │   │   └── chat/
│   │   │       ├── domain/
│   │   │       │   └── message_model.dart
│   │   │       ├── data/
│   │   │       │   └── chat_repository.dart
│   │   │       └── presentation/
│   │   │           ├── bloc/
│   │   │           │   └── chat_bloc.dart
│   │   │           └── screens/
│   │   │               └── chat_screen.dart
│   │   └── main.dart
│   ├── pubspec.yaml                   # Dependencias Flutter
│   ├── conectar_backend.ps1           # Script netsh para puente red
│   └── android/                       # Configuración Android
├── cmd/
│   └── api/                           # Backend (FASE 0-9)
│       └── main.go
├── internal/
│   ├── core/
│   │   ├── domain/
│   │   │   ├── user.go
│   │   │   ├── pet.go
│   │   │   ├── user_profile.go                        # (Fase 9)
│   │   │   ├── match.go                               # (Fase 9)
│   │   │   ├── report.go                              # (Fase 8)
│   │   │   └── blacklist.go                           # (Fase 8)
│   │   └── services/
│   │       ├── auth_service.go                        # (Fase 1, actualizado Fase 8)
│   │       ├── auth_service_test.go                   # (Fase 7)
│   │       ├── identity_service.go                    # (Fase 8 - R-SEC-01)
│   │       ├── otp_service.go                         # (Fase 8)
│   │       ├── report_service.go                      # (Fase 8 - R-SEC-04)
│   │       ├── report_service_test.go                 # (Fase 8)
│   │       ├── user_service.go                        # (Fase 9)
│   │       ├── match_service.go                       # (Fase 9 - actualizado)
│   │       ├── math_test.go                           # (Fase 7)
│   │       └── ...
│   ├── transport/
│   │   ├── http/
│   │   │   ├── user_handler.go                        # (Fase 9)
│   │   │   ├── match_handler.go                       # (Fase 9 - actualizado)
│   │   │   └── ...
│   │   └── websocket/
│   └── platform/
│       └── database/
├── .github/                           # GitHub Actions (FASE 7)
│   └── workflows/
│       └── ci.yml                     # CI/CD Pipeline (2-job: quality-gate + build-and-push)
├── k8s/                               # Manifiestos Kubernetes (FASE 6)
│   ├── backend.yaml                   # Deployment + LoadBalancer Service
│   ├── postgres.yaml                  # Deployment + ClusterIP Service
│   ├── redis.yaml                     # Deployment + ClusterIP Service
│   └── minio.yaml                     # Deployment + LoadBalancer Service
├── Dockerfile                         # Containerización del Backend (FASE 6)
├── .dockerignore                      # Archivos a ignorar en construcción
├── uploads/                           # Almacenamiento local de imágenes
├── documentation/                     # Documentación por fase
├── docker-compose.yml                 # Orquestación de servicios (Docker)
├── go.mod                             # Dependencias de Go
├── go.sum
├── .env                               # Variables de entorno
└── README.md                          # Este archivo
```

**Servicios Implementados**:

| Servicio          | Fase | Descripción                                  | Archivos            |
| ----------------- | ---- | -------------------------------------------- | ------------------- |
| AuthService       | 1,8  | Autenticación, JWT, blacklist check          | auth_service.go     |
| PetService        | 2    | Gestión de mascotas, búsqueda                | pet_service.go      |
| MatchService      | 3,9  | Algoritmo de matching con compatibilidad     | match_service.go    |
| ChatService       | 4    | WebSocket distribuido, Redis Pub/Sub         | chat_service.go     |
| FileUploadService | 2    | Upload a MinIO, gestión de archivos          | upload_service.go   |
| IdentityService   | 8    | Verificación de identidad, RUT validation    | identity_service.go |
| OTPService        | 8    | Generación OTP 6-dígito, Redis storage       | otp_service.go      |
| ReportService     | 8    | Sistema de reportes con auto-ban (3 strikes) | report_service.go   |
| UserService       | 9    | Gestión de perfiles demográficos             | user_service.go     |

**Notas Arquitectónicas**:

- Backend: Mantiene estructura tradicional en raíz (cmd/, internal/)
- Frontend: Aislado en carpeta app/ (proyecto Flutter independiente)
- Monorepo: Git único, pero dos proyectos completamente separados
- Comunicación: API REST (Dio) + WebSocket (web_socket_channel)
- Containerización (Fase 6): Dockerfile para Backend, multi-stage build
- Orquestación (Fase 6): Kubernetes manifiestos YAML en carpeta k8s/
- Networking (Fase 6): LoadBalancer para API/MinIO, ClusterIP para Postgres/Redis
- CI/CD (Fase 7): GitHub Actions con 2 jobs (quality-gate + build-and-push)
- Security (Fase 8): Identity verification, anti-multicuenta, blacklist, auto-ban after 3 reports
- Matchmaking (Fase 9): GetSwipeDeck con hard constraints, UserProfile demográfico, Match state machine

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
- **Fase 5** (Completada): Frontend Flutter, Clean Architecture, BLoC, arquitectura híbrida
- **Fase 6** (Completada): Dockerización, Kubernetes, orquestación de contenedores
- **Fase 7** (Completada): CI/CD pipeline, testing unitario, linting, vulnerability scanning, Docker push
- **Fase 8** (Completada): Verificación de identidad (R-SEC-01), anti-multicuentas (R-SEC-02), blacklist (R-SEC-03), auto-ban system (R-SEC-04)
- **Fase 9** (Completada): Matchmaking inteligente, perfiles enriquecidos, algoritmo de compatibilidad, flujo de swipe/pending/respond
- **Fase 10** (Planificada): Integración de chat post-match, cierre de adopciones, feedback del adoptante
- **Fase 11** (Planificada): Machine Learning para recomendaciones, scoring dinámico

## Documentación Adicional

- [Fase 0](documentation/Fase-0.md): Infraestructura, Docker, estructura base
- [Fase 1](documentation/Fase-1.md): Autenticación, seguridad, JWT y Bcrypt
- [Fase 2](documentation/Fase-2.md): Gestión de mascotas, uploads, middleware, OCR
- [Fase 3](documentation/Fase-3.md): Matchmaking, geolocalización, búsqueda SQL
- [Fase 4](documentation/Fase-4.md): Chat distribuido, WebSocket, Redis, seguridad real-time
- [Fase 5](documentation/Fase-5.md): Frontend Flutter, Clean Architecture, BLoC, arquitectura híbrida
- [Fase 6](documentation/Fase-6.md): Dockerización, Kubernetes, orquestación, LoadBalancer, ClusterIP
- [Fase 7](documentation/Fase-7.md): CI/CD pipeline, testing unitario, linting automático, escaneo de vulnerabilidades, Docker push
- [Fase 8](documentation/Fase-8.md): Seguridad robusta, verificación de identidad, anti-multicuentas, sistema de reportes con auto-ban
- [Fase 9](documentation/Fase-9.md): Matchmaking inteligente, perfiles enriquecidos, algoritmo de compatibilidad, flujo de interacción

## Autor
