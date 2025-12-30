# Fase 12: Despliegue Cloud y DevOps - Etapa 8 "Hacia la Nube y el Mundo"

## Introducción

La Fase 12 documenta exhaustivamente cómo PAWS fue desplegado en producción cloud con una arquitectura moderna y escalable. Aunque nominalmente es una "Fase" posterior, esta documentación se completa durante la **Etapa 8** como la culminación de toda la arquitectura técnica del proyecto. PAWS abandonó localhost y se convirtió en una aplicación accesible globalmente a través de tres servicios cloud principales: Supabase (base de datos), Railway (backend API), y Vercel (frontend web).

## Objetivos de Fase 12

Documentar y explicar:

1. Estrategia de despliegue cloud para diferentes componentes
2. Integración de GitHub con Railway y Vercel (CI/CD automático)
3. Gestión de variables de entorno sensibles
4. Configuración de base de datos cloud (Supabase)
5. Monitoreo, logs y debugging en producción
6. Escalabilidad y performance en cloud
7. Costos y optimizaciones

## Arquitectura General de Despliegue

```
┌─────────────────────────────────────────────────────────────┐
│                        INTERNET GLOBAL                      │
└─────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                │             │             │
                ▼             ▼             ▼
        ┌──────────────┐ ┌──────────┐ ┌──────────────┐
        │   VERCEL     │ │ RAILWAY  │ │  SUPABASE    │
        │ (Frontend)   │ │ (Backend)│ │ (Database)   │
        └──────────────┘ └──────────┘ └──────────────┘
             │                │              │
        ┌─────┴─────┐  ┌──────┴──────┐  ┌────┴─────┐
        │  CDN 200+ │  │ Go API      │  │PostgreSQL│
        │   ciudades│  │ Port 8080   │  │ Pool 6543│
        │           │  │             │  │          │
        │index.html │  │ /api/v1/... │  │ 99.99%   │
        │main.dart.js  │ WebSocket   │  │ uptime   │
        │assets/    │  │ gRPC (fut)  │  │ Backups  │
        └───────────┘  └─────────────┘  └──────────┘
             │                │              │
        Deploy via:    Deploy via:    Managed by:
        GitHub         GitHub         Supabase
        Push           Push           CLI/Dashboard
             │                │              │
        Vercel Auto      Railway Auto   Config.json
        Build            Build          schema.sql
```

## Componente 1: Base de Datos - Supabase

### ¿Qué es Supabase?

Supabase es un backend open-source que proporciona PostgreSQL hosted en AWS con interfaz tipo Firebase. Incluye:

- **PostgreSQL 15**: Motor relacional con extensiones (PostGIS para geolocalización)
- **Row Level Security (RLS)**: Control de acceso a nivel de fila
- **Connection Pooler**: Gestión de conexiones (puerto 6543)
- **Backups Automáticos**: Diarios, retenidos 7 días
- **Replicas**: Lectura en múltiples regiones
- **Dashboard Web**: Interfaz para gestión de BD, usuarios, políticas

### Creación y Configuración de Supabase

#### Paso 1: Crear Proyecto

```
1. Ir a https://supabase.com
2. Sign Up con GitHub (OAuth)
3. Nueva organización "PAWS"
4. Nuevo proyecto "paws-production"
5. Seleccionar región AWS (ej: us-west-2 para Latinoamérica)
6. Configurar contraseña postgres fuerte (copiar a .env después)
7. Click "Create New Project" (esperar 2 minutos)
```

#### Paso 2: Obtener Credenciales

Después de creado, Supabase proporciona:

```
Project URL (REST API):    https://sfpgibalxrecscjcevrk.supabase.co
Anon Key (público):        eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Service Role Key (secreto): eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Database Host (pooler):     aws-0-us-west-2.pooler.supabase.com
Database Port (pooler):     6543
Database Name:              postgres
Database User:              postgres
Database Password:          (la que ingresaste)
```

#### Paso 3: Construir CONNECTION STRING para DATABASE_URL

```
postgresql://postgres:YanoespistaShow123---@aws-0-us-west-2.pooler.supabase.com:6543/postgres?pgbouncer=true
                      ↑                        ↑                                       ↑
                   Password                 Host                                  Pooler enabled
```

**Importante**: Usar puerto 6543 (Connection Pooler) en vez de 5432 (direct connection). El pooler distribuye conexiones inteligentemente y evita timeout en infraestructura moderna.

#### Paso 4: Agregar Extensiones (PostGIS, UUID)

En Supabase Dashboard → SQL Editor, ejecutar:

```sql
-- PostGIS para geolocalización (Fase 3)
CREATE EXTENSION IF NOT EXISTS postgis;

-- UUID para identificadores únicos
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- PgCrypto para funciones criptográficas
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

#### Paso 5: Habilitar Row Level Security (RLS)

En Supabase Dashboard → Authentication → Policies:

```sql
-- Política: Usuarios solo ven su propio perfil
CREATE POLICY "Users can only see their own profile"
ON public.users FOR SELECT
USING (auth.uid()::text = id::text);

-- Política: Usuarios solo pueden actualizar su propio perfil
CREATE POLICY "Users can only update their own profile"
ON public.users FOR UPDATE
USING (auth.uid()::text = id::text);
```

### Migraciones Automáticas en Producción

Cuando el backend (Go) se despliega en Railway con DATABASE_URL de Supabase:

```go
// cmd/api/main.go

func main() {
    // GORM automáticamente aplica migraciones
    err := database.DB.AutoMigrate(
        &domain.User{},
        &domain.UserProfile{},
        &domain.Pet{},
        &domain.Match{},
        &domain.Message{},
        &domain.Review{},
        &domain.Report{},
        &domain.BlacklistEntry{},
    )
    if err != nil {
        log.Fatal("Error en migraciones:", err)
    }
}
```

**Ventajas**:

- No requiere scripts `migration up` manuales
- Idempotente: `CREATE TABLE IF NOT EXISTS` (safe to repeat)
- Reproducible: mismo schema en local y nube
- Zero downtime: migraciones in-place en PostgreSQL

### Backups y Disaster Recovery

Supabase proporciona:

- **Backups Diarios**: Automáticos, retenidos 7 días
- **Point-in-Time Recovery**: Restaurar a cualquier momento dentro de los últimos 7 días
- **Replicas de Lectura**: En múltiples regiones (plan Enterprise)
- **Sync Automático**: Cambios en primary se replican a replicas en <1ms

**Acceso a Backups**:

```
Supabase Dashboard
  → Backups
  → Seleccionar fecha/hora
  → Descargar .sql dump
  → Restaurar a instancia local para testing
```

## Componente 2: Backend - Railway

### ¿Qué es Railway?

Railway es una plataforma de despliegue (PaaS) que:

- Conecta tu repositorio GitHub via OAuth
- Detecta lenguaje (Go, Python, Node, etc.)
- Compila automáticamente
- Dockeriza
- Despliega en servidores globales
- Proporciona URL pública con HTTPS automático
- Escalado automático basado en CPU/memoria

### Despliegue en Railway

#### Paso 1: Conectar GitHub

```
1. Ir a https://railway.app
2. Sign Up con GitHub (OAuth)
3. Crear nuevo "Project"
4. Click "Deploy from GitHub"
5. Autorizar Railway en GitHub
6. Seleccionar repositorio: RicketyMajor/PAWS-2.0
7. Seleccionar rama: develop
8. Click "Deploy"
```

#### Paso 2: Configurar Variables de Entorno

Railway detecta `go.mod`, sabe que es Go, y busca configuración:

```
Railway Dashboard
  → Proyecto PAWS
  → Servicio "api" (auto-detectado)
  → Variables (pestaña)
  → Agregar variables:

PORT=8080
JWT_SECRET=secreto_super_seguro_paws_2025
DATABASE_URL=postgresql://...supabase.com:6543/postgres?pgbouncer=true
ENABLE_ASYNC_FEATURES=false
```

**Importante**: Nunca hardcodear credenciales. Siempre usar variables de entorno en Railway dashboard.

#### Paso 3: Despliegue Automático

Después de configuradas variables:

```
Railway auto-ejecuta:
  1. git clone repo
  2. go mod download (descargar dependencias)
  3. go build (compilar binario)
  4. Crear Dockerfile (auto-generado)
  5. docker build (construir imagen)
  6. docker push (subir a registry de Railway)
  7. docker run (ejecutar contenedor)
  8. Health check (verifica que backend responde)
  9. Asignar URL: paws-20-production.up.railway.app
 10. Logs en tiempo real en dashboard
```

#### Paso 4: Ver Logs en Tiempo Real

```
Railway Dashboard
  → Logs (pestaña)
  → "Conexión a Base de Datos exitosa"
  → "Migración de base de datos completada"
  → "Servidor ejecutándose en puerto 8080"
  → Cada request/error aparece en tiempo real
```

### Escalado Automático

Railway monitorea CPU y memoria:

```
Si backend usa:
  - < 50% CPU/mem: 1 instancia (pequeña)
  - 50-80% CPU/mem: 1 instancia (mediana)
  - > 80% CPU/mem: Escala a 2 instancias (automático)
  - > 80% en 2 inst: Escala a 3 (y así)

Resultado: aplicación siempre responde rápido
```

### Monitoreo y Alertas

Railway proporciona métricas:

```
Dashboard → Metrics
  - CPU usage
  - Memory usage
  - Network IN/OUT
  - HTTP Status codes (200, 404, 500, etc)
  - Response time percentiles (p50, p95, p99)

Alertas (futuro):
  - CPU > 80% por 5 minutos
  - Error rate > 5%
  - Response time > 2s
```

## Componente 3: Frontend - Vercel

### ¿Qué es Vercel?

Vercel es una plataforma de hosting para aplicaciones web estáticas y dinámicas:

- Conecta GitHub
- Auto-detecta framework (Next.js, Vue, Nuxt, Flutter Web, etc.)
- Compila proyecto
- Sube a CDN global en 200+ ciudades
- Proporciona HTTPS automático
- Integración con domain personalizado

### Despliegue en Vercel

#### Paso 1: Conectar GitHub

```
1. Ir a https://vercel.com
2. Sign Up con GitHub (OAuth)
3. Click "Import Project"
4. Seleccionar repositorio: RicketyMajor/PAWS-2.0
5. Vercel auto-detecta Flutter Web
6. Click "Deploy"
```

#### Paso 2: Configurar Root Directory

Vercel necesita saber dónde está el proyecto web:

```
Vercel Dashboard
  → Project Settings
  → Root Directory: app
  → Build Command: flutter build web --release
  → Output Directory: build/web
  → Save
```

#### Paso 3: Agregar Variables de Entorno (Opcional)

Si necesitaras variables en tiempo de build (no recomendado para URLs):

```
Vercel Dashboard
  → Settings
  → Environment Variables

Nota: Las URLs se hardcodean en api_constants.dart
      usando kReleaseMode para detectar ambiente
```

#### Paso 4: Deploy Automático

```
Developer hace: git push origin develop
  ↓
GitHub webhook notifica a Vercel
  ↓
Vercel auto-ejecuta:
  1. git clone repo (rama develop)
  2. cd app
  3. flutter build web --release
  4. Toma contenido de app/build/web/
  5. Sube a CDN global
  6. Asigna URL: paws-<hash>.vercel.app (preview)
  7. Espera confirmación para producción
  ↓
Si todo OK: URL producción paws.vercel.app (con dominio personalizado)
```

#### Paso 5: Dominio Personalizado

```
Vercel Dashboard
  → Domains
  → Add Domain
  → paws.app (si lo compraste)
  → DNS records a los de Vercel
  → Esperar propagación (hasta 24 horas)
  ↓
Resultado: https://paws.app es tu URL pública
```

### Performance en Vercel

Vercel CDN optimiza automáticamente:

```
Usuario en México request paws.app
  ↓
DNS resolver lo redirecciona a CDN más cercana (México City edge)
  ↓
CDN sirve HTML/CSS/JS localmente (<10ms latencia)
  ↓
JavaScript hace fetch a Railway backend
  ↓
Railway en us-west-2 responde (<100ms latencia)
  ↓
Browser renderiza app Flutter
```

**Métricas**:

- Time to First Byte (TTFB): <100ms (edge cacheado)
- Core Web Vitals: LCP <2.5s, FID <100ms, CLS <0.1
- Build time: 5-10 minutos (Flutter Web es lento)
- Deploy: Instant (CDN invalidation)

## CI/CD Pipeline Integrado (Sin Fase 7 Manual)

A diferencia de Fase 7 (GitHub Actions manual), Etapa 8 usa CI/CD nativo de plataformas:

### Railway CI/CD (Automático)

```
Flujo:
  1. Developer: git commit -m "Fix login bug"
  2. Developer: git push origin develop
  3. GitHub webhook → Railway
  4. Railway detecta cambios en rama develop
  5. Auto-construye y despliega backend
  6. Logs aparecen en dashboard
  7. API actualizada en <5 minutos
  8. Sin intervención manual
```

### Vercel CI/CD (Automático)

```
Flujo:
  1. Developer: flutter format --set-exit-if-changed
  2. Developer: git commit -m "Update UI"
  3. Developer: git push origin develop
  4. GitHub webhook → Vercel
  5. Vercel detecta cambios en rama develop
  6. Build preview automático
  7. PR en GitHub: "Vercel Preview Ready" (enlace)
  8. Developer prueba en preview antes de mergear a main
  9. Merge a main → Vercel auto-deploya a producción
 10. CDN invalidada, usuarios ven cambios en segundos
```

**Ventajas sobre Fase 7**:

- No requiere GitHub Actions `.yml` manual
- Feedback inmediato (preview URLs en PRs)
- Rollback instantáneo (git revert + push)
- Logs integrados en dashboard

## Gestión de Secretos y Variables Sensibles

### Jerarquía de Seguridad

```
TIER 1: Locales (Desarrollo)
  ├─ .env (nunca commitear)
  ├─ Contiene credenciales locales
  └─ Variables de desarrollo

TIER 2: CI/CD (Railway/Vercel Dashboard)
  ├─ Variables encriptadas en rest
  ├─ Injected en tiempo de deploy
  ├─ No visible en logs
  ├─ Acceso limitado a admins
  └─ Auditado: quién cambió qué, cuándo

TIER 3: Secretos Rotados
  ├─ JWT_SECRET: Cambiar cada 3 meses
  ├─ DATABASE_URL: Cambiar password en Supabase cada 6 meses
  ├─ Tokens de terceros: Actualizar si expiran
  └─ Revoke old secrets en Supabase/Railway
```

### Variables Actuales en Producción (Railway)

```
PORT=8080                                          # Público (app escucha)
JWT_SECRET=secreto_super_seguro_paws_2025        # Secreto (firmar JWTs)
DATABASE_URL=postgresql://...supabase.com:6543    # Credenciales BD
ENABLE_ASYNC_FEATURES=false                       # Feature flag
```

### Variables en Frontend (api_constants.dart)

```dart
// NUNCA en código:
static const String apiKey = "sk-xxx";  // WRONG
static const String jwtSecret = "secret";  // WRONG

// SIEMPRE dinámico:
static const String baseUrl = kReleaseMode
    ? 'https://paws-20-production.up.railway.app/api/v1'
    : 'http://localhost:8080/api/v1';  // OK
```

## Monitoreo y Debugging en Producción

### Logs de Railway

```
Dashboard → Logs

Ejemplo (login exitoso):
[INFO] 2025-12-30 14:35:20 AuthService: User "juan@example.com" logged in successfully
[INFO] 2025-12-30 14:35:21 AuthService: JWT issued with role=adopter
[DEBUG] 2025-12-30 14:35:21 AuthMiddleware: Token valid for userID=123

Ejemplo (error):
[ERROR] 2025-12-30 14:40:15 ReportService: User #999 not found
[WARN] 2025-12-30 14:40:15 BanUserManual: Report for non-existent user
[ERROR] 2025-12-30 14:40:15 AdminHandler: 500 Internal Server Error
```

### Health Check Endpoint

Agregar en main.go (futuro):

```go
r.GET("/health", func(c *gin.Context) {
    c.JSON(200, gin.H{
        "status": "ok",
        "timestamp": time.Now(),
        "database": "connected",
        "version": "1.0.0",
    })
})
```

Railway puede configurar health check:

```
Railway Dashboard
  → Deploy Settings
  → Health Check: GET /health
  → Interval: 30s
  → Timeout: 5s
  ↓
Si /health falla, Railway marca instancia como unhealthy
y no le envía más traffic
```

### Métricas Importantes

**Backend (Railway)**:

```
Request rate: ?/segundo
Response time: p50, p95, p99
Error rate: % de 5xx
CPU usage: % de capacidad
Memory usage: % de capacidad
Database connections: # activas
JWT validity: % válidos vs inválidos
```

**Frontend (Vercel)**:

```
Page load time
Core Web Vitals (LCP, FID, CLS)
Build time
Deploy frequency
CDN hit ratio
Bandwidth usage
```

## Costos Estimados

### Supabase (Base de Datos)

```
Gratis (hasta cierto punto):
  - 500MB almacenamiento
  - 2GB transfer/mes
  - Connection pooler

Pagado (Pro, $25/mes o más):
  - Storage ilimitado
  - 100GB transfer/mes
  - 500 conexiones simultáneas
  - Soporte prioritario
```

**Para PAWS**: Tier gratuito suficiente inicialmente (< 50 usuarios activos).

### Railway (Backend)

```
Gratis (si eres nuevo):
  - $5/mes de credits iniciales
  - Después: pago por uso

Pricing:
  - Compute: $0.39/vCPU/hora
  - Almacenamiento: $0.10/GB/mes
  - Bandwidth: $0.10/GB (outbound)

Ejemplo (1 instancia pequeña, 24/7):
  - 0.5 vCPU: ~$14/mes
  - 1GB RAM: ~$7/mes
  - Almacenamiento: ~$1/mes
  ───────────────────────
  Total: ~$22/mes (muy barato)
```

### Vercel (Frontend)

```
Gratis:
  - Build time: 100 horas/mes
  - Deployments ilimitados
  - CDN global
  - HTTPS automático

Pagado (Pro, $20/mes):
  - Build time: 400 horas/mes
  - Soporte prioritario
  - Custom domains
  - Analytics avanzado
```

**Para PAWS**: Gratis suficiente (< 5 builds/día = 5 horas/mes).

### Total Estimado (Primeros 6 Meses)

```
Supabase:   Gratis (tier free)
Railway:    $22/mes × 6 = $132
Vercel:     Gratis
Dominio:    $12/año ÷ 12 = $1/mes × 6 = $6
────────────────────────────────
Total:      ~$138 (muy affordable para startup)
```

## Disaster Recovery y Rollback

### Scenario: Bug Crítico en Producción

```
Usuario reporta: "No puedo hacer login"

Opción 1: Rollback Inmediato (2 minutos)
  1. Ir a Railway Dashboard
  2. Ver histórico de deployments
  3. Click en deployment anterior (que funcionaba)
  4. Click "Redeploy"
  5. Backend rollback en <2 minutos
  6. Usuarios pueden login nuevamente

Opción 2: Hotfix y Redeploy (5 minutos)
  1. Desarrollador: git checkout -b hotfix/login-bug
  2. Arreglar bug en código
  3. git commit && git push origin hotfix/login-bug
  4. Railway auto-deploya
  5. Pruebas confirmadas
  6. Bug resuelto
```

### Scenario: Base de Datos Corrupta

```
Supabase detecta corrupción (muy raro):

Opción 1: Restore from Backup (10 minutos)
  1. Supabase Dashboard → Backups
  2. Seleccionar backup pre-corrupción (6 horas atrás)
  3. Click "Restore"
  4. Esperar 10 minutos
  5. Schema y datos recuperados

Opción 2: Backup Manual Local
  1. pg_dump > backup.sql (exportar esquema+datos)
  2. git add backup.sql
  3. git commit -m "Database backup $(date)"
  4. Restaurar: psql < backup.sql
```

## Best Practices en Producción

### 1. Versionamiento

```
Siempre usar tags de versión:
  git tag v1.0.0-etapa8
  git push origin v1.0.0-etapa8

Railway/Vercel pueden desplegar versión específica si es necesario
```

### 2. Monitoring Proactivo

```
Configurar alertas:
  Railway:
    - CPU > 80% por 5 min → Slack
    - Error rate > 5% → Slack
    - Database connections > 400 → Slack

  Vercel:
    - Build failure → Email
    - Deployment rollback → Email
```

### 3. Testing Pre-Deploy

```
Antes de mergear a main:
  1. flutter test (frontend)
  2. go test ./... (backend)
  3. Vercel preview URL (manual testing)
  4. Load testing (si es necesario)
```

### 4. Documentación

```
Mantener actualizado:
  - README.md con URLs de producción
  - docs/deployment.md para procesos
  - .env.example con variables necesarias (sin valores)
```

### 5. Rotación de Secretos

```
Cada 3 meses:
  - JWT_SECRET: generar nuevo, actualizar Railway, rotar clientes
  - Database password: cambiar en Supabase, actualizar DATABASE_URL
  - API keys (si hay): revisar expiraciones
```

## Checklists de Despliegue

### Pre-Deploy

- [ ] `flutter test` pasa localmente
- [ ] `go test ./...` pasa localmente
- [ ] API conecta a BD local correctamente
- [ ] Frontend web compila: `flutter build web --release`
- [ ] sin hardcoded URLs (solo kReleaseMode)
- [ ] Variables de entorno en Railway dashboard configuradas
- [ ] Dominio en Vercel configurado (o preview URL aceptable)
- [ ] README actualizado con URLs vivas

### Post-Deploy

- [ ] Vercel preview URL funciona
- [ ] Railway logs muestran "Migración completada"
- [ ] API responde a GET /health
- [ ] Login funciona (end-to-end test)
- [ ] Chat WebSocket funciona
- [ ] Mascotas cargarse (match deck)
- [ ] Ningún error 5xx en logs
- [ ] Performance aceptable (<2s response)

### Post-Production (Semanal)

- [ ] Revisar logs de Railway para errores
- [ ] Revisar Vercel analytics (Core Web Vitals)
- [ ] Verificar Supabase backups (recientes)
- [ ] Revisar uso de recursos (CPU, memoria, disk)
- [ ] Verificar ningún secret fue leakeado

## Referencias y Documentación

- **Railway Docs**: https://docs.railway.app
- **Vercel Docs**: https://vercel.com/docs
- **Supabase Docs**: https://supabase.com/docs
- **Flutter Web**: https://flutter.dev/web
- **Postgres Connection Pooling**: https://wiki.postgresql.org/wiki/Number_of_database_connections
- **DevOps Best Practices**: https://12factor.net/
- **Cloud Security**: https://owasp.org/Cloud-Security/
