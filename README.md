<div align="center">
  <!-- Reemplaza esta imagen con un logo o banner atractivo de PAWS -->
  <img src="docs/images/banner.png" alt="PAWS Logo" width="200"/>

  # PAWS Backend 🐾

  **La aplicación definitiva para conectar animales rescatados con sus familias ideales.**
  
  <p align="center">
    <img src="https://img.shields.io/badge/Go-1.25.10-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Go Version" />
    <img src="https://img.shields.io/badge/Gin-Framework-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Gin" />
    <img src="https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL" />
    <img src="https://img.shields.io/badge/RabbitMQ-FF6600?style=for-the-badge&logo=rabbitmq&logoColor=white" alt="RabbitMQ" />
    <img src="https://img.shields.io/badge/Docker-2CA5E0?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />
  </p>
</div>

---

## 📖 Acerca del Proyecto

PAWS es una plataforma interactiva, diseñada bajo una arquitectura moderna (inspirada en la dinámica de Tinder), que facilita el proceso de adopción de mascotas. El backend está construido en **Golang** utilizando el framework **Gin**, garantizando un rendimiento óptimo, manejo de concurrencia y despliegues ultrarrápidos gracias a su contenedorización.

### ✨ Funcionalidades Principales

1. **Gestión de Identidad y OTP:** Registro seguro, recuperación de contraseñas y validación de identidad en dos pasos mediante correos automatizados (Brevo API).
2. **Sistema de Swipes (Match):** Algoritmo de emparejamiento entre usuarios adoptantes y mascotas publicadas por rescatistas.
3. **Chat en Tiempo Real:** Comunicación fluida entre el rescatista y el adoptante a través de WebSockets, permitiendo la coordinación directa una vez que ocurre un "Match".
4. **Roles Dinámicos:** Los usuarios pueden cambiar de "Adoptante" a "Rescatista" desde su misma cuenta.
5. **Notificaciones y Eventos Asíncronos:** Uso de RabbitMQ para descongestionar el servidor principal y procesar correos, notificaciones Push y eventos pesados en segundo plano.

---

## 📸 Capturas de Pantalla (App Entornos)

> **Nota para el desarrollador:** *Reemplaza estos placeholders con capturas de pantalla reales (Swagger, logs o el Frontend/App Móvil funcionando) para darle más vida al repositorio.*

<div align="center">
  <table>
    <tr>
      <td align="center"><b>Autenticación y OTP</b></td>
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

## 🏗️ Arquitectura y Flujo de Datos

PAWS sigue una arquitectura limpia (Clean Architecture) dividiendo responsabilidades en Transporte, Capa Core (Lógica de negocio) y Plataforma (Infraestructura de datos).

```mermaid
graph TD
    %% Usuarios / Frontend
    User([📱 Aplicación Móvil / Web])

    %% API Gateway / Ingress
    subedge[Backend System]
        API[Gin HTTP Router / Middleware]
        WS[WebSocket Hub]
        
        %% Servicios Core
        subgraph Core Services
            Auth[Auth & OTP Service]
            Match[Match Service]
            Chat[Chat Service]
            Pet[Pet & User Service]
        end

        %% Infraestructura
        subgraph Infrastructure
            DB[(PostgreSQL)]
            Redis[(Redis)]
            Minio[☁️ AWS S3 / Minio]
        end

        %% Workers Asíncronos
        subgraph Async Workers
            RabbitMQ{RabbitMQ}
            Worker1[Email Worker]
            Worker2[Notification Worker]
            Brevo[Brevo API / SMTP]
        end
    endsubedge

    %% Conexiones
    User -- HTTP/REST --> API
    User -- wss:// --> WS

    API --> Auth
    API --> Match
    API --> Pet
    
    WS --> Chat

    %% Base de datos y Caché
    Auth -- Almacena código temporal --> Redis
    Match -- Registra Swipe --> DB
    Chat -- Guarda historial --> DB
    Pet -- Metadata --> DB
    Pet -- Sube Imágenes --> Minio

    %% Flujo Asíncrono
    Auth -- Cola de correos --> RabbitMQ
    Match -- Cola de matches --> RabbitMQ
    RabbitMQ --> Worker1
    RabbitMQ --> Worker2
    Worker1 --> Brevo
```

### 🗂️ Estructura del Directorio

```text
PAWS-2.0/
├── cmd/
│   └── api/                # Entrypoint de la aplicación (main.go)
├── internal/
│   ├── core/               # Lógica de negocio (Dominio y Casos de uso)
│   │   ├── domain/         # Modelos de base de datos (GORM)
│   │   ├── services/       # Lógica central (Auth, Match, Pets, Chat, etc.)
│   │   └── workers/        # Consumidores de RabbitMQ
│   ├── infrastructure/     # Integraciones externas
│   │   ├── email/          # Integración con Brevo (SMTP/HTTP)
│   │   └── messaging/      # Cliente y publicador de RabbitMQ
│   ├── platform/           # Bases de datos y almacenamiento
│   │   └── database/       # Conexión y configuración de PostgreSQL
│   └── transport/          # Capa de presentación / HTTP
│       └── http/           # Controladores, Middleware y Routers (Gin)
├── Dockerfile              # Construcción multi-stage optimizada (Alpine)
├── docker-compose.yml      # Entorno local (Postgres, RabbitMQ, Redis, Minio)
├── go.mod                  # Dependencias de Go
└── Makefile                # Comandos rápidos de compilación y ejecución
```

---

## 🚀 Guía de Instalación (Getting Started)

Sigue estos pasos para levantar el entorno de PAWS en tu máquina local.

### 1. Prerrequisitos
- **Go** >= 1.25.10
- **Docker** y **Docker Compose**
- **Git**

### 2. Variables de Entorno (`.env`)
Clona el repositorio y crea un archivo `.env` en la raíz del proyecto. Toma como base el siguiente ejemplo:

```env
# Database Config
DATABASE_URL=postgres://user:password@localhost:5432/paws?sslmode=disable

# Redis Config (Para OTPs)
REDIS_URL=redis://localhost:6379/0

# JWT Secrets
JWT_SECRET=tu_super_secreto_seguro_para_jwt

# RabbitMQ (Para tareas asíncronas)
RABBITMQ_URL=amqp://user:password@localhost:5672/

# Brevo API (Para envío de correos OTP)
BREVO_API_KEY=tu_api_key_de_brevo
BREVO_SENDER_EMAIL=paws@tudominio.com

# Asynchronous Toggles
ENABLE_ASYNC_FEATURES=true
```

### 3. Levantar Infraestructura Local
Usa el archivo `docker-compose.yml` para levantar las bases de datos y colas de mensajería requeridas:

```bash
docker-compose up -d
```
*Esto levantará PostgreSQL, RabbitMQ, Redis y Minio.*

### 4. Ejecutar la Aplicación
Con las dependencias locales corriendo, ejecuta el backend:

```bash
go run cmd/api/main.go
```
*El servidor se iniciará en `http://localhost:8080`.*

---

## ☁️ Despliegue en Producción (Serverless / Docker)

Este proyecto está optimizado para plataformas como **Render**, **Railway** o **Fly.io** gracias a su `Dockerfile` Multi-Stage.

- Construye un binario estático sin CGO (`CGO_ENABLED=0`).
- Imagen final basada en `alpine` (ultra ligera, ~20MB).
- CA Certificates instalados para soportar conexiones seguras a integraciones de terceros.

Simplemente conecta este repositorio a Render como un **"Web Service"**, usando Docker como entorno, y la plataforma se encargará del resto.

> **💡 Tip de Mantenimiento:** El endpoint `/api/v1/health` se puede usar para conectar a herramientas como UptimeRobot y evitar que los contenedores en capa gratuita se "duerman".

---

*Diseñado y desarrollado para el ecosistema PAWS. ❤️*
