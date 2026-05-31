<div align="center">
  <img src="docs/images/banner.png" alt="PAWS Logo" width="200"/>

  # PAWS

  **La plataforma integral para conectar animales rescatados con sus familias ideales.**
  
  <p align="center">
    <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
    <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
    <img src="https://img.shields.io/badge/Go-1.25.10-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Go Version" />
    <img src="https://img.shields.io/badge/Gin-Framework-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Gin" />
    <img src="https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL" />
    <img src="https://img.shields.io/badge/RabbitMQ-FF6600?style=for-the-badge&logo=rabbitmq&logoColor=white" alt="RabbitMQ" />
    <img src="https://img.shields.io/badge/Docker-2CA5E0?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />
  </p>
</div>

---

## Acerca del Proyecto

PAWS es una plataforma interactiva, disenada bajo una arquitectura moderna (inspirada en la dinamica de Tinder), que facilita el proceso de adopcion de mascotas. Este repositorio es un **Monorepo** que contiene todo el ecosistema del proyecto:
- **Frontend:** Construido en **Flutter (Dart)**, compilado para Web y desplegado en **Vercel**.
- **Backend:** Construido en **Golang** (Framework **Gin**) y desplegado en **Render**.

### Funcionalidades Principales

1. **Gestion de Identidad y OTP:** Registro seguro, recuperacion de contrasenas y validacion de identidad en dos pasos mediante correos automatizados (Brevo API).
2. **Sistema de Swipes (Match):** Algoritmo de emparejamiento entre usuarios adoptantes y mascotas publicadas por rescatistas.
3. **Chat en Tiempo Real:** Comunicacion fluida entre el rescatista y el adoptante a traves de WebSockets, permitiendo la coordinacion directa una vez que ocurre un "Match".
4. **Roles Dinamicos:** Los usuarios pueden cambiar de "Adoptante" a "Rescatista" desde su misma cuenta.
5. **Notificaciones y Eventos Asincronos:** Uso de RabbitMQ para descongestionar el servidor principal y procesar correos, notificaciones Push y eventos pesados en segundo plano.

---

## Capturas de Pantalla (Entornos)

<div align="center">
  <table>
    <tr>
      <td align="center"><b>Autenticacion y OTP</b></td>
      <td align="center"><b>Feed de Swipes</b></td>
      <td align="center"><b>Chat en Tiempo Real</b></td>
    </tr>
    <tr>
      <td><img src="docs/images/auth_placeholder.png" alt="Auth Screen" width="250"/></td>
      <td><img src="docs/images/swipe_placeholder.png" alt="Swipe Feed" width="250"/></td>
      <td><img src="docs/images/chat_placeholder.png" alt="Chat Screen" width="250"/></td>
    </tr>
  </table>
</div>

---

## Arquitectura y Flujo de Datos

El ecosistema PAWS se divide entre el cliente interactivo y un backend robusto basado en Clean Architecture.

```mermaid
graph TD
    subgraph Frontend - Flutter / Vercel
        App[Flutter Web App .dart]
        UI[UI Components]
        State[State Management / Core]
        App --> UI
        App --> State
    end

    subgraph Backend System - Go / Render
        API[Gin HTTP Router / Middleware]
        WS[WebSocket Hub]
        
        subgraph Core Services
            Auth[Auth & OTP Service]
            Match[Match Service]
            Chat[Chat Service]
            Pet[Pet & User Service]
        end

        subgraph Infrastructure
            DB[(PostgreSQL - Neon.tech)]
            Redis[(Redis - Upstash)]
            Cloudinary[Cloudinary CDN]
        end

        subgraph Async Workers
            RabbitMQ{RabbitMQ}
            Worker1[Email Worker]
            Worker2[Notification Worker]
            Brevo[Brevo API / SMTP]
        end
    end

    %% Conexiones Cliente-Servidor
    State -- HTTP/REST --> API
    State -- wss:// --> WS

    %% Flujo Interno del Backend
    API --> Auth
    API --> Match
    API --> Pet
    WS --> Chat

    Auth -- Almacena codigo temporal --> Redis
    Match -- Registra Swipe --> DB
    Chat -- Guarda historial --> DB
    Pet -- Metadata --> DB
    Pet -- Sube Imagenes --> Cloudinary

    Auth -- Cola de correos --> RabbitMQ
    Match -- Cola de matches --> RabbitMQ
    RabbitMQ --> Worker1
    RabbitMQ --> Worker2
    Worker1 --> Brevo
```

### Estructura del Monorepo

Este repositorio contiene tanto la aplicacion cliente como el servidor, organizados de la siguiente manera:

```text
PAWS-2.0/
├── app/                    # FRONTEND (Flutter / Dart)
│   ├── lib/
│   │   ├── core/           # Configuraciones, utilidades y manejo de estado global
│   │   ├── features/       # Vistas y modulos principales (Auth, Swipe, Chat, Profile)
│   │   └── main.dart       # Entrypoint de la aplicacion movil/web
│   ├── web/                # Archivos estaticos para Flutter Web
│   ├── vercel.sh           # Script de despliegue automatizado para Vercel
│   └── pubspec.yaml        # Dependencias de Dart y Flutter
│
├── cmd/                    # BACKEND (Go)
│   └── api/                # Entrypoint del servidor (main.go)
│
├── internal/               # CODIGO FUENTE BACKEND (Clean Architecture)
│   ├── core/               # Logica de negocio (Dominio y Casos de uso)
│   │   ├── domain/         # Modelos de base de datos (GORM)
│   │   ├── services/       # Logica central (Auth, Match, Pets, Chat, etc.)
│   │   └── workers/        # Consumidores de RabbitMQ
│   ├── infrastructure/     # Integraciones externas
│   │   ├── email/          # Integracion con Brevo (SMTP/HTTP)
│   │   └── messaging/      # Cliente y publicador de RabbitMQ
│   ├── platform/           # Bases de datos y almacenamiento
│   │   └── database/       # Conexion a PostgreSQL (Neon.tech)
│   └── transport/          # Capa HTTP
│       └── http/           # Controladores, Middleware y Routers (Gin)
│
├── Dockerfile              # Construccion multi-stage del Backend (Alpine)
├── docker-compose.yml      # Entorno local (PostgreSQL, RabbitMQ, Redis)
├── go.mod                  # Dependencias de Go
└── Makefile                # Comandos rapidos de compilacion y ejecucion
```

---

## Guia de Instalacion (Local)

Sigue estos pasos para levantar el ecosistema completo en tu maquina local.

### 1. Prerrequisitos
- **Flutter SDK** (Para el Frontend)
- **Go** >= 1.25.10 (Para el Backend)
- **Docker** y **Docker Compose**
- **Git**

### 2. Entorno del Backend (.env)
En la raiz del proyecto, crea un archivo `.env` utilizando los servicios Cloud requeridos:

```env
# Database Config (Neon.tech)
DATABASE_URL=postgres://user:password@hostname.neon.tech/dbname?sslmode=require

# Redis Config (Upstash)
REDIS_URL=rediss://default:password@hostname.upstash.io:6379

# Cloudinary (Almacenamiento de imagenes)
CLOUDINARY_URL=cloudinary://key:secret@cloud_name

# JWT Secrets
JWT_SECRET=tu_secreto_seguro_para_jwt

# Asynchronous Toggles
ENABLE_ASYNC_FEATURES=true

# Brevo API (Envio de correos)
BREVO_API_KEY=tu_api_key_de_brevo
BREVO_SENDER_EMAIL=paws@tudominio.com
```

### 3. Levantar la Infraestructura Local
Si no deseas conectarte a las nubes de Neon/Upstash durante el desarrollo, puedes levantar copias locales con Docker:

```bash
docker-compose up -d
```

### 4. Ejecutar los Proyectos

**Para el Backend (Go):**
```bash
go run cmd/api/main.go
```
*El servidor HTTP y WebSocket se iniciara en `http://localhost:8080`.*

**Para el Frontend (Flutter):**
En una nueva terminal, navega a la carpeta `app/` e inicia la aplicacion web o el emulador:
```bash
cd app
flutter pub get
flutter run -d chrome
```

---

## Despliegue en Produccion (Serverless / Docker)

El ecosistema esta disenado para ser operado bajo una arquitectura distribuida:

1. **Frontend (App Flutter)**: Desplegado en **Vercel** usando Flutter Web para un aprovisionamiento global y rapido. Vercel ejecuta `app/vercel.sh` para la compilacion.
2. **Backend (Go API)**: Desplegado en **Render** como un Web Service, aprovechando la construccion Multi-Stage en el `Dockerfile` (imagen base `alpine` ultra ligera y binario compilado a traves de `CGO_ENABLED=0`).
3. **Base de Datos**: PostgreSQL alojado en **Neon.tech**.
4. **Almacenamiento en Cache**: Redis alojado en **Upstash**.
5. **Multimedia**: **Cloudinary** actua como CDN para el almacenamiento de imagenes.

Al conectar este repositorio a Render y Vercel, ambas plataformas detectan sus respectivos directorios y gestionan las compilaciones de forma automatizada.

> El endpoint `/api/v1/health` esta disponible para integraciones de monitoreo continuo (por ejemplo, UptimeRobot).
