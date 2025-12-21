# Fase 6: Infraestructura y Orquestación - De Desarrollo a Producción

## Introducción

La Fase 6 marca la transformación definitiva de PAWS de una aplicación "desarrollador-friendly" a una arquitectura de clase empresarial lista para producción. Esta fase implementa dos grandes cambios: (1) Containerización completa del código Go usando Docker, permitiendo portabilidad garantizada entre máquinas, y (2) Migración de Docker Compose a Kubernetes, el estándar de facto en la industria para orquestación de contenedores.

Este salto desde "correr binarios directamente en la máquina" a "ejecutar en un cluster Kubernetes" es lo que diferencia a un desarrollador de aplicaciones de un Arquitecto de Software. Implementaremos patrones de red avanzados (LoadBalancer, ClusterIP), manifiestos declarativos (YAML), y resolveremos el complejo desafío de controlar un cluster Kubernetes alojado en Windows desde WSL2 (Linux virtual).

## Objetivos de la Fase 6

1. Empaquetar aplicación Go en contenedor Docker ligero (multi-stage build)
2. Crear cluster Kubernetes de un solo nodo en Windows
3. Generar manifiestos YAML declarativos para todos los servicios (Backend, PostgreSQL, Redis, MinIO)
4. Implementar patrones de red avanzados: LoadBalancer (público) y ClusterIP (interno)
5. Configurar variables de entorno en manifiestos (ConfigMap ready)
6. Establecer comunicación intra-cluster entre servicios usando DNS interno
7. Permitir control remoto del cluster K8s desde WSL2 (kubectl)
8. Implementar almacenamiento de objetos S3-compatible con MinIO
9. Documentar arquitectura de flujo de datos en cluster
10. Preparar proyecto para despliegue en cloud (AWS EKS, Google GKE, Azure AKS)

## Stack Tecnológico Nuevo - Infraestructura

### Containerización

- **Docker**: 27.0.0 (aproximado)
- **Base Image (Builder)**: golang:alpine
- **Base Image (Runtime)**: alpine:latest
- **Estrategia**: Multi-stage build (compilación separada de ejecución)

### Orquestación

- **Kubernetes**: v1.28+ (local cluster)
- **kubectl**: Cliente de línea de comandos
- **Manifiestos**: YAML (deployment.yaml, service.yaml)
- **Patrón**: Declarativo (describe "qué quiero" no "cómo hacerlo")

### Almacenamiento de Objetos

- **MinIO**: Latest (S3-compatible)
- **Protocolo**: AWS S3 API
- **Uso**: Reemplazo de almacenamiento local (/uploads)

### Networking en Cluster

- **LoadBalancer**: Expone servicios al exterior (Backend, MinIO Console)
- **ClusterIP**: Servicio interno, solo accesible desde dentro del cluster (PostgreSQL, Redis)
- **DNS Interno**: Service Names se resuelven como hostnames

## Cambios en la Estructura del Proyecto

### Antes (Fase 5): Docker Compose Únicamente

```
PAWS-2.0/
├── docker-compose.yml          # Define servicios en Docker
├── cmd/
│   └── api/
│       └── main.go
├── internal/
├── app/
│   ├── lib/
│   └── pubspec.yaml
└── documentation/
```

### Después (Fase 6): Kubernetes Completo

```
PAWS-2.0/
├── Dockerfile                   # NUEVO: Empaquetamiento de Backend
├── .dockerignore                # NUEVO (Opcional): Archivos a ignorar
├── docker-compose.yml           # Mantiene compatibilidad local
├── k8s/                         # NUEVA CARPETA: Manifiestos Kubernetes
│   ├── backend.yaml             # Deployment + Service LoadBalancer
│   ├── postgres.yaml            # Deployment + Service ClusterIP
│   ├── redis.yaml               # Deployment + Service ClusterIP
│   └── minio.yaml               # Deployment + Service LoadBalancer
├── kubectl                      # NUEVO: Binario kubectl (opcional)
├── cmd/
│   └── api/
│       └── main.go              # Sin cambios, pero ahora en Docker
├── internal/
├── app/
│   └── lib/
│       └── core/
│           └── constants/
│               └── api_constants.dart  # Sigue apuntando a 192.168.0.4:8080
└── documentation/
```

**Cambios Clave**:

- Dockerfile para compilar Go en contenedor
- Carpeta k8s/ con 4 manifiestos YAML
- docker-compose.yml aún funciona (compatibilidad hacia atrás)
- Backend ahora es imagen Docker, no binario directo

## Detalles Técnicos Implementados

### 1. Docker: De "Artesanal" a "Contenedores"

#### Problema Original

```
Fase 5 (Desarrollo):
$ go run ./cmd/api/main.go
(Binario directo en máquina)

Problemas:
- Go debe estar instalado
- Dependencias globales podrían entrar en conflicto
- "Funciona en mi máquina pero no en producción"
```

#### Solución: Dockerfile Multi-Stage

```dockerfile
# ETAPA 1: Builder (Compilación)
FROM golang:alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o main ./cmd/api

# ETAPA 2: Runner (Ejecución)
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
```

**Ventajas del Multi-Stage Build**:

1. **Imagen Ligera**:

   - golang:alpine ≈ 300MB (contiene compilador)
   - alpine:latest ≈ 7MB (solo runtime)
   - Imagen final: ≈ 20-30MB (binario + base vacía)

2. **Seguridad**:

   - El compilador Go NO va en la imagen final
   - Reduce attack surface

3. **Portabilidad**:
   - Imagen corre idéntica en:
     - Tu laptop (macOS, Windows, Linux)
     - Servidor AWS
     - Laptop de colega
     - Kubernetes

#### Construcción de Imagen

```bash
# Construir imagen Docker
docker build -t paws-backend:k8s .

# Resultado: paws-backend:k8s (tag = versión)
# Puedes correr: docker run -p 8080:8080 paws-backend:k8s
```

### 2. Kubernetes: De "Composición Local" a "Orquestación Distribuida"

#### ¿Por qué Kubernetes vs Docker Compose?

**Docker Compose**:

- Bueno para: Desarrollo local
- Máximo: Un solo "nodo" (tu máquina)
- Limitaciones: Sin auto-scaling, sin rolling updates

**Kubernetes**:

- Bueno para: Producción
- Máximo: Cluster de 1000s de nodos
- Capacidades: Auto-scaling, auto-healing, rolling updates, networking avanzado

#### Arquitectura Kubernetes en PAWS

```
┌─────────────────────── CLUSTER KUBERNETES ──────────────────────┐
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    INTERNET (Windows)                     │  │
│  │                      :8080, :9001                        │  │
│  └───────────────────────┬──────────────────────────────────┘  │
│                          │                                      │
│    ┌─────────────────────┴──────────────────────┐              │
│    │ LoadBalancer (Kubernetes Service)          │              │
│    │ ├─ backend-service:8080 → Pod Backend     │              │
│    │ └─ minio-service:9001 → Pod MinIO        │              │
│    └──────────────────────────────────────────┘              │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                   CLUSTER IP (Privado)                   │ │
│  │ ├─ postgres-service:5432 (solo acceso local)            │ │
│  │ ├─ redis-service:6379 (solo acceso local)              │ │
│  │ └─ minio-service:9000 (API, acceso local desde Backend) │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  PODs (Contenedores):                                         │
│  ├─ backend (1 réplica) → Conecta a postgres y redis        │
│  ├─ postgres (1 réplica) → Base de datos                     │
│  ├─ redis (1 réplica) → Caché y Pub/Sub                     │
│  └─ minio (1 réplica) → Almacenamiento S3                   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 3. Manifiestos YAML Declarativos

Kubernetes funciona con el concepto "declarativo": describes el estado deseado, K8s lo mantiene.

#### Service (Exponer)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  type: LoadBalancer # Expone al exterior
  selector:
    app: backend # Busca Pods con label "app: backend"
  ports:
    - protocol: TCP
      port: 8080 # Puerto del Service (virtual)
      targetPort: 8080 # Puerto del Pod (real)
```

**¿Cómo funciona?**:

1. Kubernetes busca todos los Pods con `app: backend`
2. Crea un "Load Balancer" que distribuye tráfico entre ellos
3. Desde Windows: localhost:8080 → Service → Pod
4. Si hay 3 Pods, el tráfico se distribuye entre los 3

#### Deployment (Escalar)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-deployment
spec:
  replicas: 1 # Quiero 1 copia del Pod corriendo
  selector:
    matchLabels:
      app: backend # Busca Pods con este label
  template:
    metadata:
      labels:
        app: backend # Label para que el Service lo encuentre
    spec:
      containers:
        - name: backend
          image: paws-backend:k8s # Imagen Docker a ejecutar
          imagePullPolicy: Never # No buscar en Docker Registry
          ports:
            - containerPort: 8080 # Puerto dentro del Pod
          env: # Variables de entorno
            - name: DB_HOST
              value: "postgres-service" # DNS interno del cluster
```

**¿Cómo funciona?**:

1. K8s lee el Deployment
2. Ve que quiere 1 Pod con imagen `paws-backend:k8s`
3. Si no existe, crea uno
4. Si el Pod muere, K8s automáticamente lo resurrecciona
5. Si cambias `replicas: 3`, K8s crea 2 Pods más instantáneamente

### 4. Patrones de Red Avanzados

#### LoadBalancer: Exposición al Exterior

```yaml
type: LoadBalancer
```

Comportamiento:

```
Windows (localhost:8080)
    ↓
Kubernetes LoadBalancer Service
    ↓ (elige Pod al azar)
Pod Backend #1
Pod Backend #2
Pod Backend #3
```

**Puertos mapeados**:

- Backend API: localhost:8080
- MinIO Console: localhost:9001

#### ClusterIP: Comunicación Interna Segura

```yaml
type: ClusterIP
```

Comportamiento:

```
Pod Backend
    ↓
Consulta "postgres-service"
    ↓
DNS interno resuelve a IP del Service
    ↓
Tráfico enrutado a Pod PostgreSQL
```

**Ventajas**:

- Nadie desde fuera puede alcanzar PostgreSQL
- Ningún usuario puede conectar directamente a la BD
- Solo el Backend puede hablar con Postgres

### 5. Variables de Entorno en Manifiestos

En Kubernetes, las variables se definen en el YAML:

```yaml
env:
  - name: DB_HOST
    value: "postgres-service" # DNS del Service
  - name: DB_PORT
    value: "5432"
  - name: REDIS_HOST
    value: "redis-service" # DNS del Service
  - name: AWS_ENDPOINT
    value: "http://minio-service:9000"
```

**Ventaja sobre .env**:

- No necesitas archivo .env en el contenedor
- Variables viven en el cluster, no en el filesystem
- Cambia variable, reinicia Pod, cambio aplicado
- Futuro: ConfigMap para gestionar variables (versión avanzada)

### 6. Comunicación Intra-Cluster usando DNS

Kubernetes proporciona un DNS interno automático:

```
Service Name: postgres-service
Namespace: default (por defecto)
DNS Completo: postgres-service.default.svc.cluster.local

Desde Pod Backend:
$ ping postgres-service
PONG: 10.x.x.x (IP virtual del Service)
```

**Flujo Ejemplo: Backend conecta a PostgreSQL**

```
1. Backend código:
   db.Connect("postgres-service:5432")

2. Kernel del contenedor resuelve DNS:
   postgres-service → 10.x.x.x (IP del Service)

3. Tráfico TCP:
   Backend:random_port → postgres-service:5432

4. Kubernetes intercepta:
   "postgres-service" → busca Pods con label "app: postgres"
   → encuentra Pod PostgreSQL
   → redirige tráfico a Pod

5. Pod PostgreSQL recibe conexión
```

### 7. Control Remoto desde WSL2

Para operar el cluster Kubernetes desde WSL2:

```bash
# WSL2 no es Linux nativo, es Linux dentro de Hyper-V
# El cluster está en Windows, no en WSL2

# Pero kubectl (WSL) puede controlar el cluster (Windows) mediante:
# - Shared kubeconfig file
# - Network communication

# Después de habilitar cluster:
export KUBECONFIG=~/.kube/config

# Ahora desde WSL2:
$ kubectl get pods
NAME                   READY   STATUS    RESTARTS   AGE
backend-deployment-xxx    1/1     Running   0          2m
postgres-deployment-xxx   1/1     Running   0          2m
redis-deployment-xxx      1/1     Running   0          2m
minio-deployment-xxx      1/1     Running   0          2m

# Inspeccionar logs:
$ kubectl logs backend-deployment-xxx

# Ejecutar comando en Pod:
$ kubectl exec -it backend-deployment-xxx -- /bin/sh
```

### 8. MinIO: S3-Compatible Storage

MinIO es una alternativa open-source a AWS S3. Proporciona:

```yaml
image: minio/minio
ports:
  - containerPort: 9000 # API S3
  - containerPort: 9001 # Console Web
```

**En Backend, configurado como**:

```go
env:
  - name: AWS_ENDPOINT
    value: "http://minio-service:9000"  # S3 endpoint interno
  - name: AWS_ACCESS_KEY_ID
    value: "minioadmin"
  - name: AWS_SECRET_ACCESS_KEY
    value: "minioadmin"
  - name: AWS_BUCKET
    value: "paws-bucket"
```

**Backend puede hacer**:

```go
// Usar AWS SDK
s3 := s3.NewClient()
s3.PutObject("paws-bucket", "foto.jpg", data)  // Guarda en MinIO
```

**Usuario accede a consola**:

```
http://localhost:9001
Usuario: minioadmin
Contraseña: minioadmin
Ver buckets y archivos en interfaz web
```

### 9. Mapa de Flujo de Datos Completo

Cuando usuario toma una foto en la app:

```
1. Flutter (Móvil)
   └─ POST /api/v1/files/upload [JWT, foto.jpg]

2. Red (Windows)
   └─ localhost:8080

3. Kubernetes LoadBalancer (backend-service)
   └─ localhost:8080 → backend-service (virtual IP)

4. Selecciona Pod Backend al azar
   └─ Entrega a Pod Backend

5. Backend Go recibe POST
   ├─ Valida JWT
   │  └─ Consulta postgres-service:5432
   │     └─ Verifica usuario en BD
   └─ Guarda archivo
      └─ Conecta a minio-service:9000
         └─ PUT bucket/foto.jpg
            └─ MinIO almacena en /data

6. Respuesta al cliente
   ├─ {url: "https://minio:9000/paws-bucket/foto.jpg"}
   └─ Viaja de vuelta a Windows → Flutter
```

### 10. Migración de docker-compose.yml

El archivo original sigue siendo útil para desarrollo local:

```yaml
services:
  db:
    image: postgres:15-alpine
    ports:
      - "5432:5432"
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
  minio:
    image: minio/minio
    ports:
      - "9000:9000"
      - "9001:9001"
  backend:
    build: . # Construye usando Dockerfile
    ports:
      - "8080:8080"
    depends_on:
      - db
      - redis
```

**Diferencias docker-compose vs kubernetes**:

| Aspecto             | docker-compose                                | Kubernetes                      |
| ------------------- | --------------------------------------------- | ------------------------------- |
| Definición          | Servicios juntos en 1 archivo                 | Servicios en archivos separados |
| Escalado            | Manual: `docker-compose up --scale backend=3` | Automático: `replicas: 3`       |
| Reinicio automático | `restart: always`                             | Automático siempre              |
| Networking          | Crea red bridge automática                    | DNS interno del cluster         |
| Persistencia        | Volúmenes Docker                              | PersistentVolumes (K8s)         |

## Cambios Detectados desde Fase 5

| Cambio                            | Tipo          | Impacto                                 | Categoría         |
| --------------------------------- | ------------- | --------------------------------------- | ----------------- |
| **Dockerfile (nuevo)**            | Archivo       | Containerización del Backend            | Containerization  |
| **Carpeta k8s/ (nueva)**          | Estructura    | Manifiestos Kubernetes                  | Orchestration     |
| **backend.yaml**                  | Manifest      | Deployment + LoadBalancer Service       | K8s               |
| **postgres.yaml**                 | Manifest      | Deployment + ClusterIP Service          | K8s               |
| **redis.yaml**                    | Manifest      | Deployment + ClusterIP Service          | K8s               |
| **minio.yaml**                    | Manifest      | Deployment + LoadBalancer Service       | K8s               |
| **kubectl (opcional)**            | Binario       | Control remoto del cluster              | Tools             |
| **docker-compose.yml**            | Compatibility | Sigue funcionando, ahora con Dockerfile | Backwards Compat  |
| **Multi-stage build**             | Pattern       | Imagen ligera y segura                  | Optimization      |
| **Environment variables en YAML** | Configuration | Configuración declarativa               | Config Management |
| **LoadBalancer networking**       | Architecture  | Exposición al exterior                  | Networking        |
| **ClusterIP networking**          | Architecture  | Aislamiento de servicios críticos       | Security          |
| **DNS interno**                   | Networking    | postgres-service, redis-service, etc    | Discovery         |
| **imagePullPolicy: Never**        | K8s Setting   | Usa imágenes locales en desarrollo      | Development       |

## Decisiones Arquitectónicas Importantes

### 1. Multi-Stage Build vs Imagen Monolítica

**Elegido**: Multi-Stage Build
**Razón**: Reduce tamaño de imagen de 300MB a 20MB

```dockerfile
# Monolítico (incorrecto):
FROM golang:alpine
COPY . .
RUN go build -o main ./cmd/api
CMD ["./main"]
# Resultado: 300MB (incluye compilador)

# Multi-stage (correcto):
FROM golang:alpine AS builder
COPY . .
RUN go build -o main ./cmd/api

FROM alpine:latest
COPY --from=builder /app/main .
CMD ["./main"]
# Resultado: 20MB (solo binario)
```

### 2. Kubernetes Local vs Cloud

**Elegido**: Kubernetes Local (Windows/Hyper-V)
**Razón**: Desarrollo cero-costo, sintaxis idéntica a AWS/GCP/Azure

```bash
# Local (gratis)
kubectl apply -f k8s/backend.yaml

# AWS EKS (pago)
kubectl apply -f k8s/backend.yaml
# Mismo comando, solo cambia kubeconfig
```

### 3. LoadBalancer vs Ingress

**Elegido**: LoadBalancer (simple)
**Razón**: Para aplicación pequeña es suficiente

LoadBalancer: Una IP pública por Service

```
localhost:8080 → Backend
localhost:9001 → MinIO Console
```

Ingress: Una IP pública, múltiples rutas

```
localhost/api/* → Backend
localhost/minio/* → MinIO Console
```

Para Fase 6 es overkill. Fase 7 podría usar Ingress.

### 4. ConfigMap vs Variables en Manifest

**Elegido**: Variables directas en YAML (para simplicidad)
**Razón**: ConfigMap es más avanzado (Fase 7)

```yaml
# Simple (actual)
env:
  - name: DB_HOST
    value: "postgres-service"

# Avanzado (futuro)
env:
  - name: DB_HOST
    valueFrom:
      configMapKeyRef:
        name: paws-config
        key: db-host
```

### 5. Docker Compose vs Dockerfile + Kubernetes

**Elegido**: Ambos coexisten
**Razón**: Compatibilidad con developers que prefieren docker-compose

```bash
# Opción 1: docker-compose (desarrollo rápido)
docker-compose up

# Opción 2: Kubernetes (aprendizaje, producción)
kubectl apply -f k8s/
```

## Stack Completo Fase 6

| Componente           | Tecnología    | Versión   | Propósito          | Tipo        |
| -------------------- | ------------- | --------- | ------------------ | ----------- |
| **Containerization** | Docker        | 27.0.0    | Empaquetar código  | Build       |
| **Build Base**       | golang:alpine | Latest    | Compilador         | Docker      |
| **Runtime Base**     | alpine:latest | Latest    | Ejecución ligera   | Docker      |
| **Orchestration**    | Kubernetes    | v1.28+    | Cluster management | Infra       |
| **kubectl**          | -             | Bundled   | CLI para K8s       | Tools       |
| **Object Storage**   | MinIO         | Latest    | S3-compatible      | Service     |
| **Backend**          | Go            | 1.24.0    | API                | Application |
| **Database**         | PostgreSQL    | 15-alpine | Datos              | Service     |
| **Cache**            | Redis         | alpine    | Pub/Sub            | Service     |
| **Frontend**         | Flutter       | 3.24.0    | Mobile             | Application |

## Flujo de Deployment - Paso a Paso

### Fase de Desarrollo

```bash
$ go run ./cmd/api/main.go
# Backend ejecuta directamente sin contenerización
```

### Fase de Transición

```bash
$ docker-compose up
# 1. Dockerfile se construye
# 2. Backend ahora en contenedor, pero localmente
# 3. PostgreSQL, Redis, MinIO también en contenedores
# 4. Networking transparente (docker-compose lo maneja)
```

### Fase Production-Ready

```bash
# 1. Habilitar Kubernetes en Windows
# 2. Construir imagen Docker
docker build -t paws-backend:k8s .

# 3. Aplicar manifiestos Kubernetes
kubectl apply -f k8s/

# 4. Verificar estado
kubectl get pods
kubectl get services
```

### Fase Cloud (Futuro)

```bash
# 1. Push imagen a AWS ECR/Docker Hub
docker tag paws-backend:k8s 123456789.dkr.ecr.us-east-1.amazonaws.com/paws-backend:latest
docker push ...

# 2. Cambiar imagen en manifest
# image: paws-backend:k8s → image: 123456789.dkr.ecr.us-east-1.amazonaws.com/paws-backend:latest

# 3. Aplicar en AWS EKS
kubectl apply -f k8s/
```

## Comparativa: Antes vs Después Fase 6

### Antes (Fase 5)

```
Developer abre terminal
    ↓
$ go run ./cmd/api/main.go
    ↓
Binario Go corre directamente en máquina
    ↓
Accesible en localhost:8080
    ↓
Si reinicia PC: debe reiniciar todo manualmente
```

**Problemas**:

- Difícil de replicar en otro PC
- Difícil de compartir con colega
- No hay escalado
- No hay auto-healing

### Después (Fase 6)

```
Developer hace git push
    ↓
GitHub Actions construye imagen Docker
    ↓
Imagen se pushea a Docker Registry
    ↓
Kubernetes pull de imagen
    ↓
Kubernetes inicia contenedor en cluster
    ↓
Accesible en localhost:8080
    ↓
Si cluster se cae: Kubernetes automáticamente lo reinicia
    ↓
Si necesita 3 réplicas: kubectl patch replicas: 3
```

**Ventajas**:

- Idéntico en laptop, servidor, cloud
- Trivial compartir con colega (docker build && docker push)
- Escalado: cambiar número en YAML
- Auto-healing: K8s lo mantiene vivo
- Cloud-ready: Mismo código corre en AWS EKS

## Referencias y Recursos

- **Docker Documentation**: https://docs.docker.com/
- **Kubernetes Official Docs**: https://kubernetes.io/docs/
- **Multi-Stage Builds**: https://docs.docker.com/build/building/multi-stage/
- **kubectl Cheat Sheet**: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- **MinIO Documentation**: https://docs.min.io/
- **Windows Kubernetes Setup**: https://docs.microsoft.com/en-us/windows/wsl/tutorials/kubernetes
- **12 Factor App**: https://12factor.net/ (buenas prácticas para apps en contenedores)
