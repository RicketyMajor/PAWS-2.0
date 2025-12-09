# Fase 2: Gestión de Mascotas, Perfiles e Identidad

## Introducción

La Fase 2 implementa el core funcional de PAWS: la gestión completa de mascotas y el sistema de verificación de identidad. En esta fase, se establece la arquitectura de autenticación con middleware JWT, permitiendo que solo usuarios autenticados puedan interactuar con datos sensibles. Además, se introduce el almacenamiento de archivos para fotos de documentos y mascotas, así como el servicio de OCR simulado que completa el requisito R-SEC-01.

## Objetivos de la Fase 2

1. Crear modelo de datos para mascotas con atributos completos (nombre, tipo, edad, ubicación, estado)
2. Implementar CRUD de mascotas (Create, Read, Get All)
3. Crear middleware de autenticación JWT para proteger endpoints sensibles
4. Implementar sistema de subida de imágenes con validación de tipo
5. Crear servicio OCR mock que simula verificación de documentos
6. Establecer relaciones entre usuarios y mascotas (One-to-Many)

## Stack Tecnológico Actualizado

### Backend

- **Lenguaje**: Go 1.24.0
- **Framework Web**: Gin v1.11.0
- **ORM**: GORM v1.31.1
- **UUID**: github.com/google/uuid (generación de nombres únicos)

### Base de Datos

- **PostgreSQL**: Versión 15 con PostGIS 3.3
- **Tablas Nuevas**: `pets`
- **Relaciones**: User (1) -> Pets (M)

### Almacenamiento

- **Sistema de Archivos Local**: Carpeta `/uploads` para imágenes
- **Nombramiento**: UUID + extensión original (seguro contra colisiones)

## Cambios en la Estructura del Proyecto

Comparando con Fase 1, la estructura ha evolucionado de forma significativa:

```
PAWS-2.0/
├── cmd/
│   └── api/
│       └── main.go                    # (ACTUALIZADO: Rutas para Fase 2)
├── internal/
│   ├── core/
│   │   ├── domain/
│   │   │   ├── user.go               # (Sin cambios desde Fase 1)
│   │   │   └── pet.go                # NUEVO: Modelo de mascotas
│   │   └── services/
│   │       ├── auth_service.go       # (Sin cambios)
│   │       ├── pet_service.go        # NUEVO: Lógica de mascotas
│   │       ├── file_service.go       # NUEVO: Gestión de archivos
│   │       └── identity_service.go   # NUEVO: Verificación OCR
│   ├── transport/
│   │   └── http/
│   │       ├── auth_handler.go       # (Sin cambios desde Fase 1)
│   │       ├── pet_handler.go        # NUEVO: Endpoints de mascotas
│   │       ├── upload_handler.go     # NUEVO: Endpoint de carga
│   │       ├── identity_handler.go   # NUEVO: Endpoint de verificación
│   │       └── middleware/
│   │           └── auth.go           # NUEVO: Middleware JWT
│   └── platform/
│       └── database/
│           └── postgres.go            # (ACTUALIZADO: Migrate() incluye Pet)
├── uploads/                           # NUEVA carpeta: Almacenamiento local
├── docker-compose.yml
├── go.mod                             # (Sin cambios en dependencias)
├── go.sum
├── .env
└── documentation/
    └── Fase-2.md                     # Este archivo
```

## Detalles Técnicos Implementados

### 1. Modelo de Mascotas (domain/pet.go)

```go
type PetStatus string

const (
    StatusAvailable PetStatus = "available"
    StatusAdopted   PetStatus = "adopted"
    StatusPending   PetStatus = "pending"
)

type Pet struct {
    gorm.Model

    // Información Básica
    Name        string
    Type        string          // "Dog", "Cat", etc.
    Breed       string
    Age         int             // En meses o años
    Description string
    Status      PetStatus       // available, adopted, pending

    // Geolocalización
    Latitude    float64
    Longitude   float64

    // Relación con Usuario
    UserID      uint            // Foreign Key
    User        User            // Relación GORM

    // Imagen
    PhotoURL    string
}
```

**Características Importantes**:

1. **PetStatus Constants**: Enum-like pattern en Go. Previene valores inválidos.

2. **Foreign Key (UserID)**: Vincula cada mascota con su rescatista propietario.

3. **Relación GORM**:

   ```go
   User User `json:"-" gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE;"`
   ```

   - `json:"-"` evita incluir el objeto User al serializar a JSON
   - `OnDelete:CASCADE` elimina mascotas si el usuario se elimina
   - Esto garantiza integridad referencial

4. **Geolocalización Básica**: Latitude y Longitude como floats. En Fase 3, se migraría a tipos PostGIS (POINT).

5. **PhotoURL**: Almacena ruta relativa (`/uploads/uuid.jpg`)

### 2. Servicio de Mascotas (services/pet_service.go)

#### Función Create

```go
func (s *PetService) Create(name, petType, breed, description string,
    age int, lat, long float64, userID uint) (*domain.Pet, error) {
    newPet := domain.Pet{
        Name:        name,
        Type:        petType,
        Breed:       breed,
        Description: description,
        Age:         age,
        Latitude:    lat,
        Longitude:   long,
        Status:      domain.StatusAvailable,
        UserID:      userID,
    }

    if err := database.DB.Create(&newPet).Error; err != nil {
        return nil, err
    }

    return &newPet, nil
}
```

**Flujo**:

1. Crear objeto Pet con datos recibidos
2. Status siempre inicia en "available"
3. UserID se asigna desde el token JWT (Handler lo pasa)
4. GORM valida constraints de BD antes de insertar
5. Si error, retorna nil y error
6. Si éxito, retorna la mascota creada con ID generado

#### Función GetAll

```go
func (s *PetService) GetAll() ([]domain.Pet, error) {
    var pets []domain.Pet
    err := database.DB.Preload("User").
        Where("status = ?", domain.StatusAvailable).
        Find(&pets).Error
    return pets, err
}
```

**Detalles**:

1. **Preload("User")**: Carga también el usuario propietario (JOIN interno)

   - Sin Preload, el campo User estaría nulo
   - GORM ejecuta: `SELECT * FROM pets ... JOIN users ...`

2. **Where("status = ?", domain.StatusAvailable)**: Filtra solo mascotas disponibles

   - `?` es placeholder para evitar SQL injection
   - `StatusAvailable` es constante "available"

3. **Find()**: Retorna slice de todos los resultados

### 3. Servicio de Archivos (services/file_service.go)

#### Función SaveImage

```go
func (s *FileService) SaveImage(file *multipart.FileHeader) (string, error) {
    // 1. Validación de extensión
    ext := strings.ToLower(filepath.Ext(file.Filename))
    if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
        return "", errors.New("formato no permitido")
    }

    // 2. Generar nombre único
    newFileName := uuid.New().String() + ext

    // 3. Ruta destino
    dst := filepath.Join(s.uploadPath, newFileName)

    // 4-6. Copiar archivo del upload temporal al destino
    src, _ := file.Open()
    out, _ := os.Create(dst)
    io.Copy(out, src)

    // 7. Retornar ruta relativa
    return "/uploads/" + newFileName, nil
}
```

**Seguridad e Implementación**:

1. **Validación de Extensión**: Solo JPG, JPEG, PNG

   - Previene upload de ejecutables (.exe, .sh, etc.)
   - Convertir a minúsculas evita bypass con ".JPG"

2. **UUID para Nombre**:

   - `uuid.New()` genera identificador único de 128 bits
   - Evita colisiones (probabilidad astronómica)
   - Imposible adivinar nombres de archivos

3. **Stream Copy**:

   ```go
   io.Copy(out, src)
   ```

   - Copia en bloques, no carga todo en RAM
   - Eficiente incluso para archivos grandes

4. **Ruta Relativa Retornada**:
   - Se guarda "/uploads/uuid.jpg" en la BD
   - El frontend accede vía `GET /uploads/uuid.jpg`
   - Docker compose expone esta carpeta estáticamente

**Flujo Completo de Upload**:

```
POST /api/v1/files/upload
    ↓ (multipart/form-data)
FileService.SaveImage()
    ↓ Valida extensión
    ↓ Genera UUID
    ↓ Copia a ./uploads/
    ↓ Retorna "/uploads/uuid.jpg"
Response: {"url": "/uploads/uuid.jpg", "message": "..."}
    ↓
Frontend usa URL para vincular a mascota o usuario
```

### 4. Servicio de Identidad (services/identity_service.go)

```go
func (s *IdentityService) VerifyIdentity(userID uint, imageURL string) error {
    // 1. Simulación de latencia (IA procesando)
    time.Sleep(2 * time.Second)

    log.Printf("OCR procesando: %s", imageURL)

    // 2. Validaciones básicas
    if imageURL == "" {
        return errors.New("no image provided")
    }

    // 3. Buscar usuario
    var user domain.User
    if err := database.DB.First(&user, userID).Error; err != nil {
        return errors.New("usuario no encontrado")
    }

    // 4. Marcar como verificado
    user.IsVerified = true
    if err := database.DB.Save(&user).Error; err != nil {
        return err
    }

    return nil
}
```

**Propósito**:

Este es un **mock de OCR** que simula un servicio real de reconocimiento óptico de caracteres:

1. **Latencia Artificial**: `time.Sleep(2 * time.Second)` simula procesamiento
2. **Validación Fake**: En producción, una IA comprobaría el formato de DNI
3. **Implementación R-SEC-01**: Marca usuario como verificado en la BD
4. **Preparado para Futuro**: Fácil reemplazar lógica con llamada a API externa (Python con Tesseract, AWS Rekognition, etc.)

**Flujo de Implementación Real (Futuro)**:

```go
// Llamar a servicio Python en VM separada
response, err := http.Post(
    "http://identity-ai:5000/verify",
    "application/json",
    bytes.NewBufferString(`{"image_url":"...","run":"..."}`)
)
var result struct {
    IsValid bool
    ExtractedRUN string
}
json.Unmarshal(response.Body, &result)
```

### 5. Middleware de Autenticación (middleware/auth.go)

```go
func AuthMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // 1. Obtener header
        authHeader := c.GetHeader("Authorization")
        if authHeader == "" {
            c.AbortWithStatusJSON(401, gin.H{"error": "se requiere token"})
            return
        }

        // 2. Parsear "Bearer <token>"
        parts := strings.Split(authHeader, " ")
        if len(parts) != 2 || parts[0] != "Bearer" {
            c.AbortWithStatusJSON(401, gin.H{"error": "formato inválido"})
            return
        }

        tokenString := parts[1]

        // 3. Validar JWT
        token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
            // Verificar algoritmo
            if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
                return nil, fmt.Errorf("algoritmo inesperado")
            }
            // Retornar clave secreta
            secret := os.Getenv("JWT_SECRET")
            return []byte(secret), nil
        })

        // 4. Verificar validez
        if err != nil || !token.Valid {
            c.AbortWithStatusJSON(401, gin.H{"error": "token inválido"})
            return
        }

        // 5. Extraer claims y guardar en contexto
        if claims, ok := token.Claims.(jwt.MapClaims); ok {
            c.Set("userID", claims["sub"])
            c.Set("role", claims["role"])
        }

        c.Next()  // Continuar al siguiente handler
    }
}
```

**Cómo Funciona el Middleware**:

1. **Intercepta Requests**: Se ejecuta ANTES que el handler real

2. **Validación en Cadena**:

   - Header presente?
   - Formato "Bearer X"?
   - Token válido?
   - No expirado?
   - Claims válidos?

3. **AbortWithStatusJSON**: Si falla en cualquier punto, envía error y DETIENE la ejecución

4. **c.Set() / c.Get()**: Almacena datos en contexto de Gin

   - Disponibles en handlers vía `c.Get("userID")`
   - Thread-safe para cada request

5. **c.Next()**: Si todo OK, ejecuta el siguiente handler

**Aplicación en Rutas**:

```go
pets := api.Group("/pets")
pets.Use(middleware.AuthMiddleware())  // TODOS los endpoints bajo /pets requieren auth
{
    pets.POST("", petHandler.Create)
    pets.GET("", petHandler.GetAll)
}
```

**Ventajas sobre sesiones tradicionales**:

- Stateless: BD no almacena sesiones
- Escalable: Múltiples servidores sin coordinación
- Móvil-friendly: Token en header
- Seguro: Firma HMAC previene tampering

### 6. Handler de Mascotas (transport/http/pet_handler.go)

```go
func (h *PetHandler) Create(c *gin.Context) {
    // 1. Obtener UserID del contexto (del Middleware)
    userIDFloat, exists := c.Get("userID")
    if !exists {
        c.JSON(401, gin.H{"error": "no autenticado"})
        return
    }
    userID := uint(userIDFloat.(float64))

    // 2. Parse JSON
    var req CreatePetRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    // 3. Llamar servicio
    pet, err := h.service.Create(
        req.Name, req.Type, req.Breed, req.Description,
        req.Age, req.Latitude, req.Longitude, userID,
    )
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    c.JSON(201, pet)
}

func (h *PetHandler) GetAll(c *gin.Context) {
    pets, err := h.service.GetAll()
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    c.JSON(200, pets)
}
```

**Puntos Clave**:

1. **Extracción de UserID**: Del JWT en el middleware

   - JWT devuelve `sub` como float64
   - Convertimos a uint para BD

2. **Creación Automática de Usuario**: UserID se asigna implícitamente

   - El rescatista no necesita proporcionar ID
   - Se infiere del token JWT

3. **GetAll Público**: No requiere autenticación
   - Permite a adoptantes ver mascotas sin registrarse
   - En futuro: Agregar filtros por ubicación, tipo, etc.

### 7. Handler de Upload (transport/http/upload_handler.go)

```go
func (h *UploadHandler) Upload(c *gin.Context) {
    // 1. Obtener archivo del form
    file, err := c.FormFile("file")
    if err != nil {
        c.JSON(400, gin.H{"error": "campo 'file' requerido"})
        return
    }

    // 2. Procesar y guardar
    path, err := h.service.SaveImage(file)
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    // 3. Retornar URL para uso posterior
    c.JSON(200, gin.H{
        "url":     path,
        "message": "imagen subida exitosamente",
    })
}
```

**Diferencia con JSON**:

- `c.FormFile()` en lugar de `c.ShouldBindJSON()`
- Procesa `multipart/form-data` en lugar de `application/json`
- El archivo está en el campo "file" del formulario

**Uso Típico**:

```bash
curl -X POST http://localhost:8080/api/v1/files/upload \
  -H "Authorization: Bearer TOKEN" \
  -F "file=@dog.jpg"
```

### 8. Handler de Verificación de Identidad (transport/http/identity_handler.go)

```go
func (h *IdentityHandler) Verify(c *gin.Context) {
    // 1. Obtener UserID del token
    userIDFloat, _ := c.Get("userID")
    userID := uint(userIDFloat.(float64))

    // 2. Parse request
    var req VerificationRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    // 3. Llamar servicio
    err := h.service.VerifyIdentity(userID, req.DocumentImageURL)
    if err != nil {
        c.JSON(409, gin.H{"error": err.Error()})
        return
    }

    c.JSON(200, gin.H{
        "message": "Identidad verificada",
        "status":  "verified",
    })
}
```

**Flujo de Verificación**:

```
1. Usuario sube DNI → POST /files/upload → Recibe URL
2. Usuario envía URL → POST /verification/verify → IsVerified=true
3. Usuarios verificados pueden:
   - Publicar mascotas (si es rescatista)
   - Acceder a chat
   - Hacer ofertas de adopción
```

### 9. Actualización del main.go

```go
func main() {
    // ... Carga .env, conecta BD ...

    // Inyección de todas las nuevas dependencias
    petService := services.NewPetService()
    fileService := services.NewFileService()
    identityService := services.NewIdentityService()

    petHandler := transport.NewPetHandler(petService)
    uploadHandler := transport.NewUploadHandler(fileService)
    identityHandler := transport.NewIdentityHandler(identityService)

    r := gin.Default()
    r.Static("/uploads", "./uploads")  // Servir archivos estáticos

    api := r.Group("/api/v1")
    {
        // Auth (sin protección)
        auth := api.Group("/auth")
        {
            auth.POST("/register", authHandler.Register)
            auth.POST("/login", authHandler.Login)
        }

        // Mascotas
        pets := api.Group("/pets")
        pets.Use(middleware.AuthMiddleware())  // Proteger
        {
            pets.POST("", petHandler.Create)
            pets.GET("", petHandler.GetAll)
        }

        // Upload
        files := api.Group("/files")
        files.Use(middleware.AuthMiddleware())
        {
            files.POST("/upload", uploadHandler.Upload)
        }

        // Verificación
        verification := api.Group("/verification")
        verification.Use(middleware.AuthMiddleware())
        {
            verification.POST("/verify", identityHandler.Verify)
        }
    }

    r.Run(":" + port)
}
```

**Estructura de Rutas Final**:

```
POST   /api/v1/auth/register               (sin auth)
POST   /api/v1/auth/login                  (sin auth)
GET    /api/v1/pets                        (sin auth - lectura pública)
POST   /api/v1/pets                        (con auth - crear mascota)
POST   /api/v1/files/upload                (con auth - subir foto)
POST   /api/v1/verification/verify         (con auth - verificar identidad)
GET    /uploads/*                          (archivos estáticos)
```

### 10. Actualización de Migraciones (database/postgres.go)

```go
func Migrate() {
    err := database.DB.AutoMigrate(
        &domain.User{},
        &domain.BlacklistEntry{},
        &domain.Pet{},  // NUEVO
    )
    if err != nil {
        log.Fatal("Error en migración")
    }
}
```

**Cambio**: Se añade `&domain.Pet{}` a la lista de migraciones.

GORM creará automáticamente:

- Tabla `pets` con columnas de User struct
- Índices para campos indexados
- Foreign key constraints

## Flujos de Uso Completos

### Caso 1: Rescatista Publica Mascota

```
1. POST /api/v1/auth/register (rescuer)
   → Crear cuenta como rescatista

2. POST /api/v1/auth/login
   → Recibir JWT token

3. POST /api/v1/files/upload
   Header: Authorization: Bearer TOKEN
   Body: multipart/form-data file=photo.jpg
   → Recibir: /uploads/uuid.jpg

4. POST /api/v1/pets
   Header: Authorization: Bearer TOKEN
   Body: {
     "name": "Max",
     "type": "Dog",
     "breed": "Golden Retriever",
     "age": 24,
     "latitude": -33.5,
     "longitude": -70.5,
     "description": "Perro cariñoso y energético"
   }
   → Mascota creada con UserID del rescatista

5. POST /api/v1/verification/verify
   Header: Authorization: Bearer TOKEN
   Body: {"document_image_url": "/uploads/dni.jpg"}
   → Usuario marcado como verificado
```

### Caso 2: Adoptante Busca Mascotas

```
1. GET /api/v1/pets (sin autenticación)
   → Recibe lista de mascotas disponibles
   → Puede filtrar sin login

2. [Opcional] Crear cuenta de adoptante
   → Verificar identidad para hacer ofertas
   → Acceder a chat futuro
```

## Cambios Detectados desde Fase 1

| Componente          | Cambio                      | Impacto                    |
| ------------------- | --------------------------- | -------------------------- |
| **domain/**         | Nuevo archivo pet.go        | Modelos para mascotas      |
| **services/**       | Nuevo: pet_service.go       | Lógica CRUD mascotas       |
| **services/**       | Nuevo: file_service.go      | Gestión de uploads         |
| **services/**       | Nuevo: identity_service.go  | OCR mock (R-SEC-01)        |
| **transport/http/** | Nuevo: pet_handler.go       | Endpoints /pets            |
| **transport/http/** | Nuevo: upload_handler.go    | Endpoint /files/upload     |
| **transport/http/** | Nuevo: identity_handler.go  | Endpoint /verification     |
| **middleware/**     | Nuevo directorio + auth.go  | Protección JWT en rutas    |
| **main.go**         | Rutas nuevas con middleware | Nueva estructura API       |
| **postgres.go**     | Migrate() incluye Pet       | Crear tabla pets           |
| **Proyecto**        | Carpeta uploads/            | Almacenamiento local       |
| **UUID**            | Nueva dependencia           | Nombres únicos de archivos |

## Decisiones Arquitectónicas Importantes

### 1. Almacenamiento Local vs MinIO

**Actual (Fase 2)**: Archivos en disco local (`./uploads`)

**Ventajas**:

- Simple de implementar
- Sin dependencias externas
- Desarrollo local sin complicaciones

**Limitaciones**:

- No escalable para múltiples servidores
- Pérdida de archivos si servidor falla
- Sin CDN para distribución

**Plan Fase 6**: Migrar a MinIO o S3 para producción

### 2. OCR Mock vs Real

**Actual**: Mock con latencia artificial

**Ventajas**:

- Desarrollo sin IA externa
- Testeable localmente
- Estructura lista para reemplazo

**Limitaciones**:

- No valida realmente DNI
- Acepta cualquier URL

**Plan Futuro**: Integrar con:

- Tesseract (OCR local)
- AWS Rekognition
- Servicio Python dedicado

### 3. JWT sin Invalidación Inmediata

**Problema**: Token válido hasta expiración, no puede revocarse instantáneamente

**Soluciones Futuras**:

- Redis token blacklist: Verificar antes de cada request
- Token rotation: Renovar con refresh tokens
- Corta expiración: Tokens de 15 minutos

### 4. Status Enum en Aplicación vs BD

**Actual**: Constantes en Go, strings en BD

```go
const (
    StatusAvailable = "available"
)
database.DB.Where("status = ?", domain.StatusAvailable)
```

**Ventaja**: Type-safe en Go, flexible en BD

**Alternativa**: Enum nativo PostgreSQL (más restrictivo)

## Implementación de Reglas de Seguridad

### R-SEC-01: Verificación de Identidad

**Status Fase 2**: Implementado (mock)

- Endpoint `/verification/verify` actualiza `IsVerified`
- En Fase 3+: Rechazar operaciones sensibles si no verificado

```go
// Future: En PetService.Create()
if user.Role == "rescuer" && !user.IsVerified {
    return nil, errors.New("debes verificar identidad")
}
```

### R-SEC-02: Prevención de Multicuentas

**Status Fase 2**: Funcional desde Fase 1, sin cambios

### R-SEC-03: Blacklist y Baneo

**Status Fase 2**: Funcional desde Fase 1, sin cambios

## Próximos Pasos (Fase 3)

1. **Geolocalización Avanzada**: PostGIS para búsquedas radiales
2. **Filtros de Búsqueda**: Por tipo, edad, ubicación
3. **Algoritmo de Matching**: Cruzar preferencias adoptante con mascotas
4. **Perfil del Adoptante**: Preferencias y requisitos
5. **Sistema de Favoritos**: Guardar mascotas de interés
6. **Auditoría**: Registrar quién hizo qué y cuándo

## Stack de Dependencias Completo

| Paquete             | Versión | Propósito                    | Fase Añadido |
| ------------------- | ------- | ---------------------------- | ------------ |
| godotenv            | v1.5.1  | Variables de entorno         | Fase 0       |
| gorm                | v1.31.1 | ORM para BD                  | Fase 0       |
| driver/postgres     | v1.6.0  | Driver GORM PostgreSQL       | Fase 0       |
| pgx                 | v5.6.0  | Driver bajo nivel PostgreSQL | Fase 0       |
| gin                 | v1.11.0 | Framework web                | Fase 1       |
| golang.org/x/crypto | v0.46.0 | Bcrypt                       | Fase 1       |
| jwt/v5              | v5.3.0  | JSON Web Tokens              | Fase 1       |
| google/uuid         | v1.6.0  | Generación de UUIDs          | Fase 2       |

## Referencias

- GORM Relationships: https://gorm.io/docs/associations.html
- Gin Middleware: https://gin-gonic.com/docs/examples/using-middleware/
- JWT Auth Pattern: https://tools.ietf.org/html/rfc7519
- Go UUID: https://pkg.go.dev/github.com/google/uuid
- File Upload Security: https://owasp.org/www-community/vulnerabilities/Unrestricted_File_Upload
