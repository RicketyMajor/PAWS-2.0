<div align="center">
  <img src="docs/images/banner.png" alt="PAWS Logo" width="200"/>

  # PAWS

  **La aplicacion definitiva para conectar animales rescatados con sus familias ideales.**
  
  <p align="center">
    <img src="https://img.shields.io/badge/Go-1.25.10-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Go Version" />
    <img src="https://img.shields.io/badge/Gin-Framework-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Gin" />
    <img src="https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL" />
    <img src="https://img.shields.io/badge/RabbitMQ-FF6600?style=for-the-badge&logo=rabbitmq&logoColor=white" alt="RabbitMQ" />
    <img src="https://img.shields.io/badge/Docker-2CA5E0?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />
  </p>
</div>

---

## Acerca del Proyecto

PAWS es una plataforma interactiva, disenada bajo una arquitectura moderna (inspirada en la dinamica de Tinder), que facilita el proceso de adopcion de mascotas. El sistema esta compuesto por un Frontend desplegado en **Vercel** y un Backend construido en **Golang** (Framework **Gin**) desplegado en **Render**. 

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

PAWS sigue una arquitectura limpia (Clean Architecture) dividiendo responsabilidades en Transporte, Capa Core (Logica de negocio) y Plataforma (Infraestructura de datos).

```mermaid
graph TD
    User([Aplicacion Movil / Web - Vercel])

    subedge[Backend System - Render]
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
    endsubedge

    User -- HTTP/REST --> API
    User -- wss:// --> WS

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

### Estructura del Directorio

```text
PAWS-2.0/
├── cmd/
│   └── api/                # Entrypoint de la aplicacion (main.go)
├── internal/
│   ├── core/               # Logica de negocio (Dominio y Casos de uso)
│   │   ├── domain/         # Modelos de base de datos (GORM)
│   │   ├── services/       # Logica central (Auth, Match, Pets, Chat, etc.)
│   │   └── workers/        # Consumidores de RabbitMQ
│   ├── infrastructure/     # Integraciones externas
│   │   ├── email/          # Integracion con Brevo (SMTP/HTTP)
│   │   └── messaging/      # Cliente y publicador de RabbitMQ
│   ├── platform/           # Bases de datos y almacenamiento
│   │   └── database/       # Conexion y configuracion de PostgreSQL
│   └── transport/          # Capa de presentacion / HTTP
│       └── http/           # Controladores, Middleware y Routers (Gin)
├── Dockerfile              # Construccion multi-stage optimizada (Alpine)
├── docker-compose.yml      # Entorno local
├── go.mod                  # Dependencias de Go
└── Makefile                # Comandos rapidos de compilacion y ejecucion
```

---

## Guia de Instalacion (Local)

Sigue estos pasos para levantar el entorno de PAWS en tu maquina local.

### 1. Prerrequisitos
- **Go** >= 1.25.10
- **Docker** y **Docker Compose**
- **Git**

### 2. Variables de Entorno (.env)
Clona el repositorio y crea un archivo `.env` en la raiz del proyecto utilizando los servicios Cloud (o locales) requeridos:

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

*(Opcional: Si requieres RabbitMQ de manera externa en produccion, anade RABBITMQ_URL. Para entorno local, se autoconfigura con Docker).*

### 3. Levantar Infraestructura Local
Usa el archivo `docker-compose.yml` para levantar las bases de datos locales si no quieres utilizar los servicios Cloud durante el desarrollo:

```bash
docker-compose up -d
```

### 4. Ejecutar la Aplicacion
Ejecuta el backend:

```bash
go run cmd/api/main.go
```
*El servidor se iniciara en `http://localhost:8080`.*

---

## Despliegue en Produccion (Serverless / Docker)

El ecosistema esta disenado para ser operado bajo una arquitectura distribuida:

1. **Frontend**: Desplegado en **Vercel** para un aprovisionamiento global y rapido del cliente.
2. **Backend**: Desplegado en **Render** como un Web Service, aprovechando la construccion Multi-Stage optimizada en el `Dockerfile` (imagen base `alpine` ultra ligera y binario compilado sin dependencias estaticas a traves de `CGO_ENABLED=0`).
3. **Base de Datos**: PostgreSQL alojado en **Neon.tech**.
4. **Almacenamiento en Cache**: Redis alojado en **Upstash**.
5. **Multimedia**: **Cloudinary** actua como CDN para el almacenamiento de imagenes de mascotas y usuarios.

Simplemente conecta este repositorio a Render, define las variables de entorno mencionadas anteriormente, y la plataforma gestionara el enrutamiento HTTP y los contenedores de forma automatica.

> **Nota de Mantenimiento:** El endpoint `/api/v1/health` esta disponible para integraciones de monitoreo continuo.
