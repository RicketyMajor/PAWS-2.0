# Fase 7: Cimientos de Calidad y Automatización (DevOps)

## Introducción

La Fase 7 marca el cambio más importante en la metodología de desarrollo de PAWS: pasamos de "confiar" en que el código funciona a **verificar automáticamente** que siempre funciona. Este es el momento donde instalamos "sensores sísmicos" en el edificio para detectar problemas antes de que causen daño.

Implementamos dos pilares fundamentales:

1. **Pipeline de CI/CD (Integración Continua / Despliegue Continuo)**: Automático, repeatable, confiable
2. **Estrategia de Testing (Unit Tests + Security Tests)**: Cobertura de lógica crítica

Este cambio cultural es lo que diferencia a un desarrollador de un ingeniero de software. Ya no es "funciona en mi máquina", es "funciona en todas partes, siempre".

## Objetivos de la Fase 7

1. Configurar pipeline de CI/CD con GitHub Actions
2. Automatizar validación de código en cada push/PR
3. Implementar Unit Testing para lógica crítica (UT-SEC-01)
4. Crear structure para Security Testing (SECT-01)
5. Ejecutar análisis estático (Linter - golangci-lint)
6. Ejecutar escaneo de vulnerabilidades (govulncheck)
7. Construir e publicar imagen Docker a Docker Hub
8. Documentar estrategia de testing de seguridad
9. Establecer baseline de calidad para futuras fases

## Stack Tecnológico Nuevo - DevOps & Testing

### CI/CD Orchestration

- **GitHub Actions**: Orquestador de workflows (gratuito, integrado en GitHub)
- **Triggers**: Push a main/develop, Pull Requests
- **Runners**: ubuntu-latest (Linux virtual de GitHub)
- **Matrix**: Próximamente: múltiples versiones de Go

### Testing Framework

- **Go Testing Package**: `testing` (estándar Go, sin dependencias externas)
- **Mock Pattern**: Inyección de dependencias para tests sin BD
- **Table-Driven Tests**: Múltiples casos de prueba en un solo test
- **Coverage Goal**: >80% para código crítico

### Code Quality

- **Build Verification**: `go build -v ./cmd/api`
- **Unit Tests**: `go test -v ./...`
- **Linter**: golangci-lint para análisis estático de código
- **Security Scanning**: govulncheck para vulnerabilidades en dependencias
- **Docker Build & Push**: Construcción automática y publicación a Docker Hub

## Cambios en la Estructura del Proyecto

### Nuevos Archivos Creados

```
PAWS-2.0/
├── .github/
│   ├── workflows/                          # ← NUEVO (Fase 7)
│   │   └── ci.yml                          # Pipeline de CI/CD
│   └── CODEOWNERS                          # (Futuro: definir reviewers)
├── internal/
│   └── core/
│       └── services/
│           ├── auth_service.go             # (Fase 1)
│           ├── auth_service_test.go        # ← NUEVO (Fase 7) - Unit Tests
│           ├── math_test.go                # ← NUEVO (Fase 7) - Dummy test
│           └── ...
├── Makefile                                # (Futuro) Comandos locales
├── .golangci.yml                           # (Futuro) Config del Linter
└── README.md                               # (Actualizado)
```

### Archivos Modificados

```
.github/workflows/ci.yml     ← NUEVO - Pipeline automatizado
internal/core/services/      ← NUEVA estructura de tests
```

## Pipeline de CI/CD (GitHub Actions)

### Filosofía

El pipeline es el "vigilante nocturno" del proyecto. Cada vez que alguien hace `git push`:

1. El código baja a servidores de GitHub
2. Se compila automáticamente (detecta errores de sintaxis)
3. Se ejecutan todos los tests
4. Si algo falla → el push se rechaza visualmente (rojo)
5. Si todo pasa → commits quedan "verificados" (verde)

### Archivo: `.github/workflows/ci.yml`

```yaml
name: PAWS Backend CI/CD Pipeline

# ¿Cuándo se activa el robot?
on:
  push:
    branches: ["main", "develop"] # Al hacer push a estas ramas
    paths:
      - "**.go" # Solo si cambiamos archivos Go
      - "go.mod"
      - ".github/workflows/ci.yml"
  pull_request:
    branches: ["main", "develop"]

jobs:
  # Fase 1: Validación de Calidad
  quality-gate:
    name: Quality Gate
    runs-on: ubuntu-latest # Usamos servidores Linux de GitHub

    steps:
      # 1. Bajar tu código al servidor
      - name: Checkout code
        uses: actions/checkout@v4

      # 2. Instalar Go en el servidor
      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: "1.24" # La versión que usas en tu go.mod

      # 3. Bajar librerías (GORM, Gin, etc.)
      - name: Install Dependencies
        run: go mod download

      # 4. Análisis de Código (Linter)
      # Detecta errores de estilo, potenciales bugs, y problemas de optimización
      - name: Run golangci-lint
        uses: golangci/golangci-lint-action@v4
        with:
          version: latest

      # 5. Escaneo de Vulnerabilidades
      # Verifica que las dependencias no tengan CVE conocidos
      - name: Run govulncheck
        run: |
          go install golang.org/x/vuln/cmd/govulncheck@latest
          govulncheck ./...

      # 6. Verificar que el código compila (Build)
      # Esto detecta errores de sintaxis graves antes de testear
      - name: Verify Build
        run: go build -v ./cmd/api

      # 7. Correr los Tests Unitarios
      # Aquí es donde se ejecutarían los casos como UT-SEC-01 y test de 3-strikes
      - name: Run Unit Tests
        run: go test -v ./...

  # Fase 2: Build y Push Docker (Solo en push a main/develop, no en PR)
  build-and-push:
    name: Build & Push Docker Image
    runs-on: ubuntu-latest
    needs: quality-gate # Solo ejecuta si quality-gate pasó
    if: github.event_name == 'push' && github.ref_name != 'refs/heads/**'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # Login a Docker Hub para hacer push de la imagen
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      # Build y push de la imagen Docker
      - name: Build and Push Docker Image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ secrets.DOCKER_USERNAME }}/paws:${{ github.sha }}
          cache-from: type=registry,ref=${{ secrets.DOCKER_USERNAME }}/paws:buildcache
          cache-to: type=registry,ref=${{ secrets.DOCKER_USERNAME }}/paws:buildcache,mode=max
```

### Flujo de Ejecución del Pipeline

```
┌──────────────────────────────────────────────────────────────────┐
│ Developer: git push origin develop                               │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│ GitHub Actions Triggered (Webhook detecta push a develop/main)   │
└────────────────────────┬─────────────────────────────────────────┘
                         │
        ┌────────────────┴────────────────┐
        │                                 │
        ▼                                 │
   FASE 1: QUALITY GATE                   │
   ════════════════════════              │
        │                                │
   ┌────┴────────┐                       │
   │ Checkout +  │                       │
   │ Setup Go    │                       │
   │ 1.24        │                       │
   └────┬────────┘                       │
        │                                │
   ┌────▼──────────────────┐            │
   │ golangci-lint         │ (Linter)   │
   │ - Sintaxis OK?        │            │
   │ - Estilos?            │            │
   │ - Code smells?        │            │
   └────┬──────────────────┘            │
        │                                │
   ┌────▼──────────────────┐            │
   │ govulncheck ./...     │ (CVE Scan) │
   │ - ¿Deps vulnerables?  │            │
   │ - ¿Updates needed?    │            │
   └────┬──────────────────┘            │
        │                                │
   ┌────▼──────────────────┐            │
   │ go build -v ./cmd/api │ (Build)    │
   │ - ¿Compila?           │            │
   └────┬──────────────────┘            │
        │                                │
   ┌────▼──────────────────┐            │
   │ go test -v ./...      │ (Unit)     │
   │ - 3-strike test OK?   │            │
   │ - Auth tests OK?      │            │
   └────┬──────────────────┘            │
        │                                │
        │ (PASS)                         │
        │                                │
        └────────────────┬───────────────┘
                         │
                         ▼
        ┌────────────────────────────────┐
        │ ALL QUALITY CHECKS PASSED      │ (BUILD → GREEN)
        └────────────────┬───────────────┘
                         │ (Solo si push, no PR)
        ┌────────────────┴───────────────┐
        │                                │
        ▼                                ▼
   FASE 2: DOCKER BUILD & PUSH
   ════════════════════════════
   ┌──────────────────────────────┐
   │ 1. Login Docker Hub          │
   │    (DOCKER_USERNAME/PASSWORD)│
   │                              │
   │ 2. Build Docker Image        │
   │    - Multistage build        │
   │    - Cache optimization      │
   │    - Tags: latest, SHA commit│
   │                              │
   │ 3. Push to Docker Hub        │
   │    → paws:${COMMIT_SHA}      │
   │    → paws:${BRANCH}-latest   │
   │    → paws:buildcache         │
   └──────────────────────────────┘
        │
        ▼
   ┌──────────────────────────────┐
   │ DEPLOYMENT READY             │
   │ Image available en Docker Hub│
   │ Ready para K8s deployment    │
   └──────────────────────────────┘
```

### Ventajas del Pipeline

| Beneficio           | Descripción                         | Ejemplo                                                   |
| ------------------- | ----------------------------------- | --------------------------------------------------------- |
| **Automatización**  | No hay que correr tests manualmente | Ahorra 5 min por push                                     |
| **Consistencia**    | Todos usan el mismo entorno         | Linux de GitHub, siempre igual                            |
| **Early Detection** | Errores encontrados inmediatamente  | Compilación falla en 30 seg, no después de deployed       |
| **Team Confidence** | Main branch siempre funciona        | Todos confían que lo que está en main no está roto        |
| **History**         | Logs guardados para auditoría       | ¿Cuándo exactamente quebró esto? → Logs de GitHub Actions |

## Estrategia de Testing

### Jerarquía de Tests

```
                    Pirámide de Testing PAWS
                           ▲
                          ╱│╲
                         ╱ │ ╲       E2E Tests (Rara: integración completa)
                        ╱  │  ╲     (ej: usuario se registra, chat, match)
                       ╱   │   ╲
                      ╱─────────╲
                     ╱     │     ╲    Integration Tests (Común: con BD real)
                    ╱      │      ╲   (ej: guardar user en Postgres)
                   ╱───────────────╲
                  ╱        │        ╲  Unit Tests (Mayoría: lógica pura)
                 ╱         │         ╲ (ej: CheckBlacklist, hash password)
                ╱─────────────────────╲
```

### Nivel 1: Unit Tests (UT-SEC-01)

**Definición**: Prueba de un componente **aislado**, sin dependencias externas.

**Patrón**:

- Preparar datos (Arrange)
- Ejecutar función (Act)
- Verificar resultado (Assert)

#### Test Example 1: `auth_service_test.go` - CheckBlacklist

```go
package services

import (
	"testing"
)

// UT-SEC-01: Validación lógica de antecedentes en Blacklist
func TestCheckBlacklist(t *testing.T) {
	// Inicializamos el servicio (como no tiene dependencias complejas aún, lo instanciamos directo)
	service := &AuthService{}

	// Caso 1: RUN Baneado
	t.Run("Debe retornar TRUE si el RUN está en blacklist", func(t *testing.T) {
		bannedRun := "12345678-9" // Este RUN lo "mockeamos" en el paso anterior
		isBanned, err := service.CheckBlacklist(bannedRun)

		if err != nil {
			t.Errorf("No se esperaba error, pero llegó: %v", err)
		}
		if !isBanned {
			t.Error("Se esperaba TRUE (Baneado), pero retornó FALSE")
		}
	})

	// Caso 2: RUN Limpio
	t.Run("Debe retornar FALSE si el RUN está limpio", func(t *testing.T) {
		cleanRun := "11111111-1"
		isBanned, err := service.CheckBlacklist(cleanRun)

		if err != nil {
			t.Errorf("No se esperaba error, pero llegó: %v", err)
		}
		if isBanned {
			t.Error("Se esperaba FALSE (Permitido), pero retornó TRUE")
		}
	})

	// Caso 3: Formato Inválido
	t.Run("Debe retornar Error si el RUN está vacío", func(t *testing.T) {
		invalidRun := ""
		_, err := service.CheckBlacklist(invalidRun)

		if err == nil {
			t.Error("Se esperaba un error por RUN vacío, pero no llegó nada")
		}
	})
}
```

**Patrón Table-Driven (Alternativa más escalable)**:

```go
func TestCheckBlacklistTableDriven(t *testing.T) {
	tests := []struct {
		name        string
		run         string
		expectBanned bool
		expectError bool
	}{
		{"ValidBannedRUN", "12345678-9", true, false},
		{"ValidCleanRUN", "11111111-1", false, false},
		{"EmptyRUN", "", false, true},
		{"InvalidFormat", "abc", false, true},
	}

	service := &AuthService{}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			isBanned, err := service.CheckBlacklist(tt.run)

			if (err != nil) != tt.expectError {
				t.Errorf("Expected error: %v, got: %v", tt.expectError, err != nil)
			}

			if isBanned != tt.expectBanned {
				t.Errorf("Expected banned: %v, got: %v", tt.expectBanned, isBanned)
			}
		})
	}
}
```

#### Test Example 2: `math_test.go` - Dummy

```go
package services

import "testing"

// TestDummy es solo para verificar que GitHub Actions funciona.
// En el futuro, aquí irán los tests de Evil PAWS.
func TestDummy(t *testing.T) {
    expected := 4
    result := 2 + 2

    if result != expected {
        t.Errorf("Matemáticas rotas: se esperaba %d pero se obtuvo %d", expected, result)
    }
}
```

### Nivel 2: Integration Tests (Futuro)

**Definición**: Prueba de múltiples componentes juntos (ej: crear usuario en BD real).

```go
func TestCreateUserIntegration(t *testing.T) {
	// Setup: Conectar a BD de prueba
	db := setupTestDB(t)
	defer db.Close()

	repo := NewUserRepository(db)
	user := &User{Name: "Juan", Email: "juan@test.com"}

	// Act
	err := repo.Create(user)

	// Assert
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	if user.ID == 0 {
		t.Error("Expected ID to be set after creation")
	}
}
```

### Nivel 3: Security Testing (SECT-01)

**Definición**: Pruebas específicamente diseñadas para encontrar vulnerabilidades comunes.

#### SECT-01: SQL Injection Testing

```go
func TestSQLInjectionBlocked(t *testing.T) {
	// Intento de inyección SQL típica
	maliciousInput := "admin' OR '1'='1"

	// Ejecutar búsqueda con input malicioso
	results, err := repo.SearchUsersByName(maliciousInput)

	// Verificar que:
	// 1. No se ejecutó el SQL inyectado
	// 2. Se retorna error o resultado vacío
	// 3. No se devuelven usuarios que no debería

	if len(results) > 0 && results[0].Email == "admin@hack.com" {
		t.Error("SQL Injection vulnerability detected!")
	}
}
```

#### SECT-02: File Upload Validation

```go
func TestFilenameValidation(t *testing.T) {
	// Archivo malicioso: contiene path traversal
	maliciousFilename := "../../etc/passwd.txt"

	// Intentar subir
	err := uploadService.ValidateAndStore(maliciousFilename, fileContent)

	// Debe rechazar
	if err == nil {
		t.Error("Expected error for malicious filename, but got nil")
	}
}
```

## Runbook: Ejecutar Tests Localmente

### Antes de hacer un PR

```bash
# 1. Descargar dependencias
go mod download

# 2. Verificar que compila
go build -v ./cmd/api

# 3. Ejecutar todos los tests
go test -v ./...

# 4. (Opcional) Ver cobertura
go test -cover ./...

# 5. (Opcional) Generar reporte HTML de cobertura
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

### En el CI/CD (Automático)

```bash
# GitHub Actions ejecuta estos comandos automáticamente
# cuando detecta push a main/develop

Step 1: Checkout code
Step 2: Setup Go 1.23
Step 3: go mod download
Step 4: go build -v ./cmd/api
Step 5: go test -v ./...
```

### Interpretar Resultados

#### Éxito

```
$ go test -v ./...

=== RUN   TestCheckBlacklist
=== RUN   TestCheckBlacklist/Debe_retornar_TRUE_si_el_RUN_está_en_blacklist
--- PASS: TestCheckBlacklist/Debe_retornar_TRUE_si_el_RUN_está_en_blacklist (0.00s)
=== RUN   TestCheckBlacklist/Debe_retornar_FALSE_si_el_RUN_está_limpio
--- PASS: TestCheckBlacklist/Debe_retornar_FALSE_si_el_RUN_está_limpio (0.00s)
=== RUN   TestDummy
--- PASS: TestDummy (0.00s)

ok      github.com/RicketyMajor/PAWS-2.0/internal/core/services  0.005s

Todos los tests pasaron!
```

#### Falla

```
$ go test -v ./...

=== RUN   TestCheckBlacklist
=== RUN   TestCheckBlacklist/Debe_retornar_TRUE_si_el_RUN_está_en_blacklist
--- FAIL: TestCheckBlacklist/Debe_retornar_TRUE_si_el_RUN_está_en_blacklist (0.00s)
    auth_service_test.go:15: Se esperaba TRUE (Baneado), pero retornó FALSE

FAIL
exit status 1

Un test falló! Necesita fix antes de hacer PR.
```

## Estándares de Testing PAWS

### Regla 1: ¿Qué se Testea?

**TESTEAR**:

- Lógica crítica de negocio (CheckBlacklist, validación de RUN, hashing)
- Edge cases (inputs vacíos, null, valores extremos)
- Manejo de errores (¿qué pasa si la BD cae?)
- Seguridad (SQL injection, path traversal, malicious filenames)

**NO TESTEAR** (generalmente):

- Getters/Setters triviales
- Librerías de terceros (confiamos que GORM funciona)
- UI (eso es Flutter testing, diferente mundo)

### Regla 2: Nomenclatura de Tests

```go
func TestCheckBlacklist(t *testing.T) { ... }           // Bueno
func TestCheckBlacklist_Invalid(t *testing.T) { ... }   // Bueno
func test1(t *testing.T) { ... }                        // Pésimo
func Test_cb(t *testing.T) { ... }                      // Poco claro
```

### Regla 3: Assertion Patterns

```go
// Patrón: if error != nil
if err != nil {
    t.Fatalf("Setup failed: %v", err)
}

// Patrón: Errorfd para verificar valores
if got != expected {
    t.Errorf("Expected %v, got %v", expected, got)
}

// Anti-patrón: require (importa librería externa)
require.NoError(t, err)  // Evitar dependencias

// Anti-patrón: if err != nil { panic(err) }
if err != nil {
    panic(err)  // Tests fallidos, no panics
}
```

## Flujo de Trabajo con Tests

### Antes de hacer Commit

```bash
$ git status
On branch feature/auth-blacklist

Untracked files:
  auth_service_test.go

$ go test -v ./...
--- PASS: TestCheckBlacklist/... (0.00s)
--- PASS: TestDummy (0.00s)

$ git add auth_service.go auth_service_test.go
$ git commit -m "Feat: Implement CheckBlacklist with unit tests (UT-SEC-01)"
```

### Al hacer Push (GitHub Actions se Ejecuta Automáticamente)

```
Tu: $ git push origin feature/auth-blacklist

GitHub:
  CI Started...
  Checkout code
  Setup Go 1.23
  go mod download
  go build -v ./cmd/api
  go test -v ./...

  Result: ALL PASSED! Merge ready.
  (Aparece bandera verde en tu PR)
```

### Si un Test Falla

```
GitHub Actions Output:

FAILED: Run Unit Tests

--- FAIL: TestCheckBlacklist/Debe_retornar_TRUE_si_el_RUN_está_en_blacklist (0.00s)
    auth_service_test.go:15: Se esperaba TRUE (Baneado), pero retornó FALSE

(Tu PR queda en rojo, bloqueado para merge)

Solución:
1. Lees el error
2. Fixes el código o el test
3. git commit
4. git push
5. GitHub Actions corre de nuevo
6. Ahora pasa
```

## Roadmap Futuro de Testing

### Fase 7+ Roadmap

| Versión         | Mejora                                                | Esfuerzo     |
| --------------- | ----------------------------------------------------- | ------------ |
| Fase 7 (Actual) | Unit tests básicos + CI pipeline                      | Completo     |
| Fase 7+         | Table-driven tests para todos los servicios           | 1-2 sem      |
| Fase 7+         | Integration tests con BD de prueba                    | 2-3 sem      |
| Fase 8          | Security tests (SQL injection, file upload, XSS)      | 3-4 sem      |
| Fase 9+         | Code coverage > 80% (herramienta: `go tool cover`)    | 2-3 sem      |
| Fase 10+        | Mutation testing (verificar que los tests son buenos) | 4-5 sem      |
| Fase 12+        | Load testing (¿qué pasa con 1000 usuarios?)           | Especialista |

## Arquitectura del Testing

```
┌────────────────────────────────────────────────────────┐
│ Código de Producción                                   │
│ ├── services/auth_service.go                           │
│ ├── core/domain/user.go                                │
│ └── transport/http/handler.go                          │
└────────────────────────────────────────────────────────┘
           │
           │ (Cada componente tiene tests)
           ▼
┌────────────────────────────────────────────────────────┐
│ Test Suite (en el mismo paquete, ficheros *_test.go)   │
│ ├── auth_service_test.go (Unit Tests de AuthService)   │
│ ├── user_integration_test.go (Integration Tests)       │
│ └── security_scan_test.go (Security Tests)             │
└────────────────────────────────────────────────────────┘
           │
           │ (go test ./...)
           ▼
┌────────────────────────────────────────────────────────┐
│ Go Test Runner                                         │
│ • Descubre tests (*_test.go, TestXxx functions)        │
│ • Ejecuta en paralelo (fast!)                          │
│ • Reporta PASS/FAIL                                    │
└────────────────────────────────────────────────────────┘
           │
           │ (Si local: manual)
           │ (Si CI/CD: automático)
           ▼
┌────────────────────────────────────────────────────────┐
│ GitHub Actions (Solo en CI/CD)                         │
│ • Se ejecuta en servidores de GitHub                   │
│ • En entorno Linux limpio, nunca "en mi máquina"       │
│ • Reporta GREEN o RED en PR                            │
└────────────────────────────────────────────────────────┘
```

## Troubleshooting Común

### Problema 1: "Test pasa localmente pero falla en GitHub Actions"

**Causa**: Diferencias entre OS, variables de entorno, rutas.

**Solución**:

```bash
# Ejecutar test en Docker (simular GitHub Actions localmente)
docker run --rm -v $PWD:/app -w /app golang:1.23 \
  bash -c "go test -v ./..."
```

### Problema 2: "Tests son muy lentos"

**Causa**: Tests esperando BD real, timeouts.

**Solución**: Usar Mocks

```go
// Malo: llamar BD real
func TestGetUser(t *testing.T) {
    db := openDatabase() // Lento!
    user := db.GetUser(1)
}

// Bueno: mock la BD
type MockDB struct{}
func (m *MockDB) GetUser(id int) *User {
    return &User{ID: 1, Name: "Test"}
}

func TestGetUser(t *testing.T) {
    mockDB := &MockDB{}
    user := mockDB.GetUser(1)
}
```

### Problema 3: "¿Cómo evitar datos de prueba que contaminen la BD real?"

**Solución**: Tests usan BD separada

```yaml
# .github/workflows/ci.yml
jobs:
  test:
    services:
      postgres:
        image: postgres:15-alpine
        env:
          POSTGRES_DB: paws_test # ← BD de prueba, NO la de producción
          POSTGRES_PASSWORD: test123
```

## Comparación: Antes vs Después de Fase 7

| Métrica                    | Antes (Fase 6)                                    | Después (Fase 7)                 |
| -------------------------- | ------------------------------------------------- | -------------------------------- |
| **Verificación de código** | Manual ("funciona en mi máquina")                 | Automática (GitHub Actions)      |
| **Catch de bugs**          | Después de deployed                               | Inmediatamente en PR             |
| **Confianza en main**      | Baja (alguien puede haber hecho push sin testear) | Alta (TODO en main pasó tests)   |
| **Tiempo de reviews**      | Más lento ("¿testaste esto?")                     | Más rápido (CI pasó ya)          |
| **Debugging**              | "¿Cuándo empezó a fallar?"                        | Histórico en GitHub Actions logs |
| **Ondboarding**            | Desarrolladores novatos rompen cosas              | Protegidos por tests + CI        |

## Plan de Integración con Fases Futuras
