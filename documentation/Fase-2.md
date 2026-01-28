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

## Etapa 2: Sistema de Identidad y Perfiles de Adopción (Actualización)

### Descripción General

La Etapa 2 complementa la fundación establecida en Etapa 1, añadiendo un sistema sofisticado de perfiles de usuario y algoritmo de matching inteligente. Mientras que Etapa 1 proporciona autenticación y gestión básica de mascotas, Etapa 2 introduce la capacidad de que los adoptantes creen perfiles demográficos que se utilizan para filtrar candidatos compatibles automáticamente.

**Cambio Fundamental**: De una búsqueda simple de mascotas disponibles a un sistema de recomendación basado en restricciones demográficas duras (vivienda, niños, mascotas existentes).

### Objetivos de Etapa 2

1. Crear modelo UserProfile para capturar información demográfica de adoptantes
2. Implementar algoritmo GetSwipeDeck con 3 filtros de compatibilidad
3. Crear sistema de swiping (like/dislike) para interacciones usuario-mascota
4. Implementar endpoint de respuesta para rescatistas a solicitudes de adopción
5. Extender modelo Pet con 5 campos de compatibilidad
6. Asegurar relación 1-a-1 entre Usuario y UserProfile con restricción de base de datos

### Nuevos Componentes de Dominio

#### UserProfile: Modelo de Perfil Demográfico

**Ubicación**: `internal/core/domain/user_profile.go`

```go
type HousingType string

const (
    HousingHouse    HousingType = "house"
    HousingApartment HousingType = "apartment"
    HousingParcel   HousingType = "parcel"
)

type UserProfile struct {
    ID              uint           `gorm:"primaryKey"`
    UserID          uint           `gorm:"uniqueIndex"` // Restricción 1-a-1
    Housing         HousingType
    HasYard         bool
    HasChildren     bool
    HasOtherPets    bool
    Experience      string         // "beginner", "intermediate", "expert"
    TimeAvailable   string         // "low", "medium", "high"
    CreatedAt       time.Time
    UpdatedAt       time.Time
    DeletedAt       gorm.DeletedAt
}
```

**Propósito**: Almacenar información demográfica requerida para el algoritmo de matching. Cada adoptante (role = "adopter") tiene exactamente un UserProfile.

**Relación**: One-to-One con User table, enforced by `uniqueIndex` en `user_id`. Rescatistas no tienen UserProfile.

**Campos Clave**:

- **Housing**: Tipo de vivienda (casa con patio, apartamento, parcela)
- **HasYard**: Indicador para filtrar mascotas que requieren espacio exterior
- **HasChildren**: Filtro para mascotas "buenas con niños"
- **HasOtherPets**: Filtro para mascotas compatibles con otros animales
- **Experience**: Nivel de experiencia con animales
- **TimeAvailable**: Disponibilidad de tiempo para cuidado

#### Extensión del Modelo Pet

**Cambios en**: `internal/core/domain/pet.go`

Se añaden 5 nuevos campos para compatibilidad de matching:

```go
type Pet struct {
    // ... campos existentes ...
    RequiresYard    bool           // ¿Requiere patio/espacio exterior?
    GoodWithKids    bool           // ¿Compatible con niños?
    GoodWithDogs    bool           // ¿Compatible con otros perros?
    GoodWithCats    bool           // ¿Compatible con gatos?
    EnergyLevel     string         // "low", "medium", "high"
}
```

**Impacto**: Permite rescatistas describir necesidades específicas de cada mascota. Estos campos se utilizan como predicados en el algoritmo de filtering.

### Nuevos Servicios

#### UserService: Gestión de Perfiles

**Ubicación**: `internal/core/services/user_service.go`

```go
type UserService struct {
    db *gorm.DB
}

func NewUserService(db *gorm.DB) *UserService {
    return &UserService{db: db}
}

// CreateOrUpdateProfile implementa patrón UPSERT
func (s *UserService) CreateOrUpdateProfile(userID uint, profile UserProfile) error {
    var existing UserProfile

    // Buscar si existe perfil para este usuario
    if err := s.db.Where("user_id = ?", userID).First(&existing).Error; err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            // No existe: crear nuevo
            profile.UserID = userID
            return s.db.Create(&profile).Error
        }
        return err
    }

    // Existe: actualizar campos
    return s.db.Model(&existing).Updates(profile).Error
}

func (s *UserService) GetProfile(userID uint) (*UserProfile, error) {
    var profile UserProfile
    if err := s.db.Where("user_id = ?", userID).First(&profile).Error; err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return nil, nil // No es error, usuario sin perfil aún
        }
        return nil, err
    }
    return &profile, nil
}
```

**Patrones Implementados**:

- **UPSERT Pattern**: Verifica existencia antes de crear/actualizar, garantiza 1-a-1
- **Nil Check**: GetProfile devuelve nil si no existe (fallback en MatchService)
- **Error Handling**: Diferencia entre "no encontrado" y errores de BD

#### MatchService: Algoritmo de Matching

**Ubicación**: `internal/core/services/match_service.go`

El corazón de Etapa 2 es el algoritmo GetSwipeDeck con 3 filtros de restricción dura:

```go
type MatchService struct {
    db          *gorm.DB
    petService  *PetService
}

func (s *MatchService) GetSwipeDeck(userID uint) ([]Pet, error) {
    // Paso 1: Obtener perfil del usuario
    profile, err := s.GetUserProfile(userID)
    if err != nil {
        return nil, err
    }

    // Paso 2: Si no hay perfil, devolver todas las mascotas disponibles
    // (fallback para usuarios nuevos, mejora UX)
    if profile == nil {
        var pets []Pet
        s.db.Where("status = ?", "available").
            Limit(20).
            Find(&pets)
        return pets, nil
    }

    // Paso 3-6: Construir query con filtros AND
    query := s.db.Where("status = ?", "available")

    // Excluir mascotas ya vistas (swiped)
    query = query.Not("id IN (?)", s.db.Select("pet_id").
        From("matches").
        Where("adopter_id = ?", userID))

    // FILTRO 1: Vivienda + Patio
    if profile.Housing == "apartment" {
        query = query.Where("requires_yard = ?", false)
    }

    // FILTRO 2: Niños
    if profile.HasChildren {
        query = query.Where("good_with_kids = ?", true)
    }

    // FILTRO 3: Mascotas Existentes
    if profile.HasOtherPets {
        query = query.Where("good_with_dogs = ?", true)
    }

    var pets []Pet
    if err := query.Find(&pets).Error; err != nil {
        return nil, err
    }

    return pets, nil
}

// Registrar swipe (like o dislike)
func (s *MatchService) Swipe(adopterID, petID uint, isLike bool) error {
    var match Match

    // Verificar si ya existe interacción
    exists := s.db.Where("adopter_id = ? AND pet_id = ?", adopterID, petID).
        First(&match).Error == nil

    status := "REJECTED"
    if isLike {
        status = "PENDING"
    }

    if exists {
        // Actualizar (idempotente)
        return s.db.Model(&match).Update("status", status).Error
    }

    // Crear nuevo
    newMatch := Match{
        AdopterID: adopterID,
        PetID:     petID,
        Status:    status,
    }
    return s.db.Create(&newMatch).Error
}

// Obtener solicitudes pendientes para mascota de rescatista
func (s *MatchService) GetPendingRequests(userID uint) ([]Match, error) {
    var matches []Match
    s.db.Joins("JOIN pets ON pets.id = matches.pet_id").
        Where("pets.user_id = ? AND matches.status = ?", userID, "PENDING").
        Preload("Adopter").
        Preload("Pet").
        Find(&matches)
    return matches, nil
}
```

**Algoritmo Explicado**:

1. **Sin Perfil Fallback**: Usuarios nuevos ven todas las mascotas (hasta 20) mientras completan su perfil
2. **Filtro de Vivienda**: Apartamentistas no ven mascotas que requieren patio
3. **Filtro de Niños**: Si tiene hijos, solo mascotas aptas para niños
4. **Filtro de Mascotas Existentes**: Si tiene mascotas, solo mascotas compatibles
5. **Lógica AND**: Todos los filtros deben pasar (no OR)
6. **Exclusión de Historial**: Mascota ya swiped no vuelve a aparecer

**Optimización**: Utiliza WHERE IN subquery en lugar de N+1 queries:

```go
NOT IN (SELECT pet_id FROM matches WHERE adopter_id = ?)
```

### Nuevos Handlers HTTP

#### UserHandler: Gestión de Perfiles

**Ubicación**: `internal/transport/http/user_handler.go`

```go
type UserHandler struct {
    userService  *services.UserService
    matchService *services.MatchService
}

// PUT /api/v1/profile
// Crear o actualizar perfil de usuario
func (h *UserHandler) UpdateProfile(c *gin.Context) {
    userID, exists := c.Get("user_id")
    if !exists {
        c.JSON(401, gin.H{"error": "No autorizado"})
        return
    }

    var profile domain.UserProfile
    if err := c.ShouldBindJSON(&profile); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    if err := h.userService.CreateOrUpdateProfile(userID.(uint), profile); err != nil {
        c.JSON(500, gin.H{"error": "Error al actualizar perfil"})
        return
    }

    c.JSON(200, gin.H{"message": "Perfil actualizado correctamente"})
}

// GET /api/v1/matches/candidates
// Obtener mascotas compatibles para este adoptante
func (h *UserHandler) GetSwipeDeck(c *gin.Context) {
    userID, exists := c.Get("user_id")
    if !exists {
        c.JSON(401, gin.H{"error": "No autorizado"})
        return
    }

    pets, err := h.matchService.GetSwipeDeck(userID.(uint))
    if err != nil {
        c.JSON(500, gin.H{"error": "Error al obtener candidatos"})
        return
    }

    c.JSON(200, pets)
}
```

#### MatchHandler: Interacciones de Swiping

**Ubicación**: `internal/transport/http/match_handler.go`

```go
type MatchHandler struct {
    service *services.MatchService
}

// POST /api/v1/matches/swipe
// Registrar like o dislike en mascota
func (h *MatchHandler) Swipe(c *gin.Context) {
    userID, _ := c.Get("user_id")

    var req struct {
        PetID  uint `json:"pet_id"`
        IsLike bool `json:"is_like"`
    }

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    if err := h.service.Swipe(userID.(uint), req.PetID, req.IsLike); err != nil {
        c.JSON(500, gin.H{"error": "Error al registrar acción"})
        return
    }

    c.JSON(200, gin.H{"message": "Acción registrada"})
}

// GET /api/v1/matches/requests
// Obtener solicitudes pendientes para mascotas de rescatista
func (h *MatchHandler) GetPending(c *gin.Context) {
    userID, _ := c.Get("user_id")

    matches, err := h.service.GetPendingRequests(userID.(uint))
    if err != nil {
        c.JSON(500, gin.H{"error": "Error al obtener solicitudes"})
        return
    }

    c.JSON(200, matches)
}

// POST /api/v1/matches/respond
// Rescatista acepta o rechaza solicitud de adopción
func (h *MatchHandler) Respond(c *gin.Context) {
    userID, _ := c.Get("user_id")

    var req struct {
        MatchID uint   `json:"match_id"`
        Accept  bool   `json:"accept"`
    }

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    status := "REJECTED"
    if req.Accept {
        status = "ACCEPTED"
    }

    if err := h.service.UpdateMatch(req.MatchID, userID.(uint), status); err != nil {
        c.JSON(500, gin.H{"error": "Error al responder solicitud"})
        return
    }

    c.JSON(200, gin.H{"message": "Solicitud respondida"})
}
```

### Rutas Protegidas Agregadas en main.go

```go
// Servicio de usuario y matching
userService := services.NewUserService(database.DB)
matchService := services.NewMatchService(database.DB, petService)

// Handlers
userHandler := httpTransport.NewUserHandler(userService, matchService)
matchHandler := httpTransport.NewMatchHandler(matchService)

// Rutas protegidas con JWT
protected := router.Group("/api/v1").Use(middleware.AuthMiddleware())
{
    // Perfil
    protected.PUT("/profile", userHandler.UpdateProfile)
    protected.GET("/matches/candidates", userHandler.GetSwipeDeck)

    // Swiping
    protected.POST("/matches/swipe", matchHandler.Swipe)
    protected.GET("/matches/requests", matchHandler.GetPending)
    protected.POST("/matches/respond", matchHandler.Respond)
}
```

### Cambios en Base de Datos

#### Nueva Tabla: user_profiles

AutoMigrate en main.go crea automáticamente:

```sql
CREATE TABLE user_profiles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL,  -- Restricción 1-a-1
    housing VARCHAR(50),
    has_yard BOOLEAN,
    has_children BOOLEAN,
    has_other_pets BOOLEAN,
    experience VARCHAR(50),
    time_available VARCHAR(50),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE UNIQUE INDEX idx_user_profiles_user_id ON user_profiles(user_id);
```

#### Modificaciones en Tabla: pets

Se agregan 5 columnas:

```sql
ALTER TABLE pets ADD COLUMN requires_yard BOOLEAN DEFAULT false;
ALTER TABLE pets ADD COLUMN good_with_kids BOOLEAN DEFAULT true;
ALTER TABLE pets ADD COLUMN good_with_dogs BOOLEAN DEFAULT true;
ALTER TABLE pets ADD COLUMN good_with_cats BOOLEAN DEFAULT true;
ALTER TABLE pets ADD COLUMN energy_level VARCHAR(50) DEFAULT 'medium';
```

### Tabla de Match (Existente, Usado en Etapa 2)

```sql
CREATE TABLE matches (
    id SERIAL PRIMARY KEY,
    adopter_id INTEGER NOT NULL,  -- Usuario que swipea
    pet_id INTEGER NOT NULL,      -- Mascota swiped
    status VARCHAR(50),           -- PENDING, ACCEPTED, REJECTED
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    FOREIGN KEY (adopter_id) REFERENCES users(id),
    FOREIGN KEY (pet_id) REFERENCES pets(id)
);

CREATE INDEX idx_matches_adopter ON matches(adopter_id);
CREATE INDEX idx_matches_pet ON matches(pet_id);
CREATE INDEX idx_matches_status ON matches(status);
```

### Ciclo de Vida Etapa 2

#### Flujo Adoptante

```
1. Login (Etapa 1) → Token JWT

2. PUT /api/v1/profile
   {
     "housing": "apartment",
     "has_yard": false,
     "has_children": true,
     "has_other_pets": false,
     "experience": "beginner",
     "time_available": "high"
   }
   → UserProfile creado con restricciones

3. GET /api/v1/matches/candidates
   → GetSwipeDeck filtra:
     * Status = 'available'
     * NOT swiped (NOT IN matches history)
     * NOT requires_yard (porque apartment)
     * good_with_kids = true (porque has_children)
   → Recibe lista de mascotas compatibles

4. POST /api/v1/matches/swipe
   {"pet_id": 5, "is_like": true}
   → Match(adopter=user, pet=5, status=PENDING) creado

5. Rescatista responde:
   POST /api/v1/matches/respond
   {"match_id": 1, "accept": true}
   → Match.status = ACCEPTED
```

#### Flujo Rescatista

```
1. Login (Etapa 1) + Crear mascota (Etapa 1)
   → Pet creado con campos de compatibilidad:
   {
     "requires_yard": false,
     "good_with_kids": true,
     "good_with_dogs": true,
     "energy_level": "medium"
   }

2. Adoptar espera...
   → Adoptantes hacen swipes (PENDING matches creados)

3. GET /api/v1/matches/requests
   → Obtiene todos los Match con status=PENDING para sus mascotas
   → Ve quién está interesado en adoptar

4. POST /api/v1/matches/respond
   → Acepta mejores candidatos (status=ACCEPTED)
   → Rechaza otros (status=REJECTED)
```

### Escenarios de Filtrado

**Escenario 1**: Adoptante con apartamento y niños

```
Usuario: {housing: "apartment", has_children: true, has_other_pets: false}

Filtros Aplicados:
- FILTRO 1: Vivienda → WHERE requires_yard = false
- FILTRO 2: Niños → WHERE good_with_kids = true
- FILTRO 3: Mascotas → (no aplica, no tiene mascotas)

Resultado: Solo mascotas que NO requieren patio Y son buenas con niños
```

**Escenario 2**: Adoptante con casa, sin niños, con gatos

```
Usuario: {housing: "house", has_children: false, has_other_pets: true}

Filtros Aplicados:
- FILTRO 1: Vivienda → (no aplica, puede tener patio)
- FILTRO 2: Niños → (no aplica, sin niños)
- FILTRO 3: Mascotas → WHERE good_with_dogs = true

Resultado: Mascotas que son compatibles con otros perros
Nota: good_with_cats no se usa en este filtro
```

**Escenario 3**: Adoptante nuevo sin perfil

```
Usuario: UserProfile no existe aún

Comportamiento: GetSwipeDeck fallback
- Devuelve primeras 20 mascotas disponibles
- Sin restricciones (UX improvement)
- Incentiva crear perfil luego

Flujo:
1. Usuario swipea sin perfil → ve todo
2. Crea perfil → Matches previos se conservan
3. Próximos swipes → Solo compatibles
```

### Decisiones Arquitectónicas Etapa 2

#### 1. Restricción 1-a-1 en Base de Datos vs Aplicación

**Elegida**: Base de datos con `uniqueIndex`

```go
type UserProfile struct {
    UserID uint `gorm:"uniqueIndex"` // Fuerza constraint en BD
}
```

**Ventaja**: No depende de lógica de aplicación; imposible crear duplicados incluso con concurrencia

**Alternativa**: Solo validación en aplicación (menos segura)

#### 2. Filtrado en Queries vs En Aplicación

**Elegida**: Filtrado en queries SQL

```go
query.Where("requires_yard = ?", false).
      Where("good_with_kids = ?", true)
```

**Ventaja**:

- Solo datos relevantes viajan red
- Base de datos optimiza índices
- Escalable con millones de mascotas

**Alternativa**: Fetch all, filter in Go (ineficiente)

#### 3. Hard Constraints vs Scoring

**Elegida**: Hard Constraints (AND lógica)

```
if apartment && good_with_kids → compatible
else → no compatible
```

**Ventaja**:

- Simple, predecible, rápido
- Garantiza satisfacción requisitos básicos
- Fácil de debugg y testear

**Alternativa**: Scoring/ML (más complejo, requiere training)

#### 4. Fallback para Usuarios Sin Perfil

**Elegida**: Mostrar todas las mascotas disponibles

```go
if profile == nil {
    return s.db.Where("status = ?", "available").Limit(20).Find(&pets)
}
```

**Ventaja**:

- UX fluida: usuarios pueden empezar a explorar inmediatamente
- Incentiva crear perfil (matches futuros más relevantes)

**Alternativa**: Bloquear hasta crear perfil (barrera entrada)

### Protecciones y Validaciones

#### Validación de entrada en handlers

```go
var profile domain.UserProfile
if err := c.ShouldBindJSON(&profile); err != nil {
    // JSON inválido rechazado
    c.JSON(400, gin.H{"error": err.Error()})
    return
}
```

#### Autenticación JWT requerida

```go
protected := router.Group("/api/v1").Use(middleware.AuthMiddleware())
// Todos los endpoints de Etapa 2 requieren token válido
```

#### Queries con prepared statements (GORM)

```go
// SEGURO: Parámetros bound con ?
query.Where("user_id = ?", userID)

// INSEGURO (evitado): String interpolation
// query.Where(fmt.Sprintf("user_id = %d", userID))
```

### Comparación: Etapa 1 vs Etapa 2

| Aspecto            | Etapa 1                | Etapa 2                        |
| ------------------ | ---------------------- | ------------------------------ |
| **Búsqueda**       | Lista todas mascotas   | Filtra por compatibilidad      |
| **Perfil Usuario** | Solo auth (email/pass) | Incluye datos demográficos     |
| **Interacción**    | Solo ver mascotas      | Like/Dislike + solicitudes     |
| **Algoritmo**      | N/A                    | 3 filtros AND                  |
| **Modelo Pet**     | Básico (nombre, tipo)  | Extendido + compatibilidad     |
| **Rescatista**     | Sube mascotas          | Ve solicitudes, acepta/rechaza |
| **Base de Datos**  | 4 tablas               | 5 tablas (+user_profiles)      |
| **Endpoints**      | 5 públicos/protegidos  | +5 new endpoints               |

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

## Etapa 14: Refinamiento Backend - Galería Ilimitada y Ficha Médica Completa

### Introducción a Etapa 14 (Backend)

La Etapa 14 representa una evolución arquitectónica del modelo Pet, transformándolo de un registro simple con una foto única hacia un sistema robusto de "Expediente de Adopción" con galería ilimitada de imágenes y campos completos de información médica y comportamental. Esta etapa abordó un problema crítico identificado en etapas anteriores: **las imágenes no se cargaban junto con los datos de mascotas** (problema N+1 de queries) y **faltaba información médica esencial** para tomar decisiones de adopción.

### Tabla PetImage: Normalización de la Galería

**Cambio Estructural**

Antes de Etapa 14, el modelo Pet contenía un único campo `PhotoURL` de tipo string. Esto limitaba severamente la capacidad de representar múltiples ángulos, entornos, o detalles visuales de una mascota.

```go
// ANTES (Fase 2-13)
type Pet struct {
    gorm.Model
    Name     string
    PhotoURL string  // Una sola foto
    UserID   uint
    // ... otros campos ...
}
```

En Etapa 14, se introduce una nueva tabla `PetImage` que establece una relación 1-a-N con Pet, permitiendo un número ilimitado de imágenes catalogadas por mascota.

```go
// DESPUÉS (Etapa 14+)

type PetImage struct {
    ID      uint   `gorm:"primaryKey" json:"id"`
    PetID   uint   `gorm:"index;not null" json:"pet_id"`
    URL     string `json:"url"`
    IsCover bool   `json:"is_cover"`  // Identifica la imagen de portada
}

type Pet struct {
    gorm.Model

    // Información Básica
    Name        string
    Type        string
    Breed       string
    Age         int
    Description string
    Status      PetStatus

    // Geolocalización
    Latitude   float64
    Longitude  float64
    Address    string

    // Backward Compatibility
    PhotoURL string      `json:"photo_url"`  // Mantenido para migraciones antiguas
    Images   []PetImage  `json:"images" gorm:"foreignKey:PetID;constraint:OnDelete:CASCADE;"`

    // Información Médica (NUEVO)
    IsVaccinated  bool   `json:"is_vaccinated"`
    IsSterilized  bool   `json:"is_sterilized"`
    IsDewormed    bool   `json:"is_dewormed"`
    SpecialNeeds  string `json:"special_needs"`

    // Compatibilidad Comportamental (NUEVO)
    RequiresYard  bool   `json:"requires_yard"`
    GoodWithKids  bool   `json:"good_with_kids"`
    GoodWithDogs  bool   `json:"good_with_dogs"`
    GoodWithCats  bool   `json:"good_with_cats"`
    EnergyLevel   string `json:"energy_level"`  // "low", "medium", "high"

    // Foreign Key
    UserID uint
    User   User  `json:"user" gorm:"foreignKey:UserID"`
}
```

**Cambios en la Migración**

El archivo `internal/platform/database/postgres.go` debe incluir `PetImage` en el `AutoMigrate()`:

```go
func (p *PostgresDB) Migrate() error {
    return p.DB.AutoMigrate(
        &domain.User{},
        &domain.Pet{},
        &domain.PetImage{},      // NUEVO: Tabla de imágenes
        &domain.Match{},
        &domain.UserProfile{},
        // ... otras tablas ...
    )
}
```

**Impacto en el Schema**

Antes:

```
pets table:
├── id (uint, PK)
├── name (string)
├── photo_url (string)
└── ... (otros campos)
```

Después:

```
pets table:
├── id (uint, PK)
├── name (string)
├── photo_url (string, LEGACY)
└── ... (otros campos)

pet_images table (NUEVA):
├── id (uint, PK)
├── pet_id (uint, FK indexado)
├── url (string)
└── is_cover (bool)
```

### Eager Loading: Solución al Problema N+1

**El Problema**

Después de implementar PetImage, surgió un problema crítico: cuando el backend consultaba mascotas, la relación Images no se cargaba automáticamente. Esto significaba que:

```go
// PROBLEMA: Query devuelve mascotas, pero Images está vacío
var pets []Pet
db.Find(&pets)  // SELECT * FROM pets;
// pets[0].Images = []  <-- Vacío, aunque hay registros en pet_images
```

Esto causaba que las galerías de imágenes estuviesen vacías en el frontend, aunque las fotos existieran en la base de datos. Además, si el cliente necesitaba las imágenes, requería consultas adicionales por cada mascota (patrón N+1).

**La Solución: Eager Loading con .Preload()**

GORM proporciona el método `.Preload()` para cargar relaciones explícitamente en una sola query. La solución fue aplicar sistemáticamente este patrón en todos los servicios que devuelven Pet.

```go
// backend/internal/services/pet_service.go

func (s *PetService) GetAll() ([]domain.Pet, error) {
    var pets []domain.Pet
    err := s.db.Preload("User").Preload("Images").
        Where("status = ?", domain.StatusAvailable).
        Find(&pets).Error
    return pets, err
}

func (s *PetService) GetByID(id uint) (*domain.Pet, error) {
    var pet domain.Pet
    err := s.db.Preload("User").Preload("Images").
        First(&pet, id).Error
    return &pet, err
}

func (s *PetService) SearchNearby(lat, lon float64, radiusKm float64) ([]domain.Pet, error) {
    var pets []domain.Pet
    query := s.db.Where(
        "6371 * acos(cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + sin(radians(?)) * sin(radians(latitude))) <= ?",
        lat, lon, lat, radiusKm,
    ).Preload("User").Preload("Images")

    err := query.Find(&pets).Error
    return pets, err
}
```

**Patrón en MatchService**

El servicio de matching es crítico porque carga múltiples mascotas para el swipe deck. El eager loading aquí es esencial para rendimiento.

```go
// backend/internal/services/match_service.go

func (s *MatchService) GetSwipeDeck(userID uint, lat, lon float64) ([]domain.Pet, error) {
    var pets []domain.Pet

    query := s.db.Preload("Images").Preload("User").
        Where("status = ?", domain.StatusAvailable).
        Where("user_id != ?", userID)

    // Filtros de búsqueda geográfica y demográfica...

    err := query.Find(&pets).Error
    return pets, err
}

func (s *MatchService) GetAcceptedMatches(adopterID uint) ([]domain.Match, error) {
    var matches []domain.Match
    err := s.db.Preload("Pet.User").
        Preload("Pet.Images").  // CRÍTICO: Sin esto, la galería está vacía
        Where("adopter_id = ? AND status = ?", adopterID, domain.MatchAccepted).
        Find(&matches).Error
    return matches, err
}

func (s *MatchService) GetAdopterPendingMatches(adopterID uint) ([]domain.Match, error) {
    var matches []domain.Match
    err := s.db.Preload("Pet.Images").
        Preload("Pet").
        Where("adopter_id = ? AND status = ?", adopterID, domain.MatchPending).
        Find(&matches).Error
    return matches, err
}

func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
    var matches []domain.Match
    err := s.db.Joins("JOIN pets ON matches.pet_id = pets.id").
        Preload("Pet.Images").
        Preload("Pet.User").
        Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
        Find(&matches).Error
    return matches, err
}

func (s *MatchService) GetRescuerMatches(rescuerID uint) ([]domain.Match, error) {
    var matches []domain.Match
    err := s.db.Joins("JOIN pets ON matches.pet_id = pets.id").
        Preload("Pet.Images").
        Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchAccepted).
        Find(&matches).Error
    return matches, err
}
```

**Impacto en Rendimiento**

- **Antes**: 1 query GET /pets + 50 queries GET /pets/{id}/images = 51 queries totales
- **Después**: 1 query GET /pets con .Preload("Images") = 2 queries (1 JOIN)
- **Mejora**: ~96% reducción en queries para swipe deck de 50 mascotas

### Manejo de Multipart Form Data

**CreatePetForm DTO**

El endpoint POST /pets ahora recibe un formulario multipart/form-data que incluye archivos y campos de texto.

```go
// backend/internal/transport/http/pet_handler.go

type CreatePetForm struct {
    Name         string  `form:"name" binding:"required"`
    Type         string  `form:"type" binding:"required"`
    Breed        string  `form:"breed"`
    Age          int     `form:"age"`
    Description  string  `form:"description"`
    Latitude     float64 `form:"latitude"`
    Longitude    float64 `form:"longitude"`
    Address      string  `form:"address"`

    // Información médica
    IsVaccinated bool   `form:"is_vaccinated"`
    IsSterilized bool   `form:"is_sterilized"`
    IsDewormed   bool   `form:"is_dewormed"`
    SpecialNeeds string `form:"special_needs"`

    // Compatibilidad
    RequiresYard bool   `form:"requires_yard"`
    GoodWithKids bool   `form:"good_with_kids"`
    GoodWithDogs bool   `form:"good_with_dogs"`
    EnergyLevel  string `form:"energy_level"`
}

func (h *PetHandler) Create(c *gin.Context) {
    var form CreatePetForm

    // Bind del formulario (campos de texto)
    if err := c.ShouldBind(&form); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    // Extracción de archivos
    formMultipart, err := c.MultipartForm()
    if err != nil {
        c.JSON(400, gin.H{"error": "Error procesando multipart"})
        return
    }

    files := formMultipart.File["images"]  // Array de archivos

    // Validación de cantidad
    if len(files) > 10 {
        c.JSON(400, gin.H{"error": "Máximo 10 fotos permitidas"})
        return
    }

    if len(files) == 0 {
        c.JSON(400, gin.H{"error": "Se requiere al menos 1 foto"})
        return
    }

    // Procesamiento de archivos
    uploadedURLs, err := h.fileService.SaveMultipleImages(c.Request.Context(), files)
    if err != nil {
        c.JSON(500, gin.H{"error": "Error al guardar imágenes"})
        return
    }

    // Obtener usuario autenticado
    userID, exists := c.Get("userID")
    if !exists {
        c.JSON(401, gin.H{"error": "No autenticado"})
        return
    }

    // Llamar al servicio
    newPet, err := h.service.Create(services.CreatePetInput{
        UserID:       userID.(uint),
        Name:         form.Name,
        Type:         form.Type,
        Breed:        form.Breed,
        Age:          form.Age,
        Description:  form.Description,
        Latitude:     form.Latitude,
        Longitude:    form.Longitude,
        Address:      form.Address,
        ImageURLs:    uploadedURLs,
        IsVaccinated: form.IsVaccinated,
        IsSterilized: form.IsSterilized,
        IsDewormed:   form.IsDewormed,
        SpecialNeeds: form.SpecialNeeds,
        RequiresYard: form.RequiresYard,
        GoodWithKids: form.GoodWithKids,
        GoodWithDogs: form.GoodWithDogs,
        EnergyLevel:  form.EnergyLevel,
    })

    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    c.JSON(201, newPet)
}
```

### PetService.Create() con Transacción

El servicio debe crear tanto el registro Pet como los registros PetImage en una transacción atómica. Si alguno falla, ambos se revierten.

```go
// backend/internal/services/pet_service.go

type CreatePetInput struct {
    UserID       uint
    Name         string
    Type         string
    Breed        string
    Age          int
    Description  string
    Latitude     float64
    Longitude    float64
    Address      string
    ImageURLs    []string
    IsVaccinated bool
    IsSterilized bool
    IsDewormed   bool
    SpecialNeeds string
    RequiresYard bool
    GoodWithKids bool
    GoodWithDogs bool
    EnergyLevel  string
}

func (s *PetService) Create(input CreatePetInput) (*domain.Pet, error) {
    // Determinar foto de portada (primera imagen)
    mainPhoto := ""
    if len(input.ImageURLs) > 0 {
        mainPhoto = input.ImageURLs[0]
    }

    // Construir objeto Pet
    newPet := domain.Pet{
        UserID:       input.UserID,
        Name:         input.Name,
        Type:         input.Type,
        Breed:        input.Breed,
        Age:          input.Age,
        Description:  input.Description,
        Status:       domain.StatusAvailable,
        Latitude:     input.Latitude,
        Longitude:    input.Longitude,
        Address:      input.Address,
        PhotoURL:     mainPhoto,  // Backward compatibility
        IsVaccinated: input.IsVaccinated,
        IsSterilized: input.IsSterilized,
        IsDewormed:   input.IsDewormed,
        SpecialNeeds: input.SpecialNeeds,
        RequiresYard: input.RequiresYard,
        GoodWithKids: input.GoodWithKids,
        GoodWithDogs: input.GoodWithDogs,
        EnergyLevel:  input.EnergyLevel,
    }

    // Transacción atómica
    err := s.db.Transaction(func(tx *gorm.DB) error {
        // Paso 1: Crear registro Pet
        if err := tx.Create(&newPet).Error; err != nil {
            return fmt.Errorf("error al crear mascota: %w", err)
        }

        // Paso 2: Crear registros PetImage
        if len(input.ImageURLs) > 0 {
            var images []domain.PetImage
            for i, url := range input.ImageURLs {
                images = append(images, domain.PetImage{
                    PetID:   newPet.ID,
                    URL:     url,
                    IsCover: (i == 0),  // Primera imagen es portada
                })
            }
            if err := tx.Create(&images).Error; err != nil {
                return fmt.Errorf("error al guardar imágenes: %w", err)
            }
        }

        return nil
    })

    if err != nil {
        return nil, err
    }

    // Recargar con relaciones
    s.db.Preload("User").Preload("Images").First(&newPet, newPet.ID)

    return &newPet, nil
}
```

### Patrones de Consulta Mejorados

**GetAll con Paginación**

```go
func (s *PetService) GetAllPaginated(page, pageSize int) ([]domain.Pet, int64, error) {
    var pets []domain.Pet
    var total int64

    offset := (page - 1) * pageSize

    err := s.db.Model(&domain.Pet{}).
        Count(&total).
        Offset(offset).
        Limit(pageSize).
        Preload("User").
        Preload("Images").
        Where("status = ?", domain.StatusAvailable).
        Find(&pets).Error

    return pets, total, err
}
```

**Búsqueda Filtrada por Compatibilidad**

```go
func (s *PetService) SearchByCompatibility(filters FilterInput) ([]domain.Pet, error) {
    var pets []domain.Pet

    query := s.db.Preload("User").Preload("Images")

    // Filtros opcionales
    if filters.GoodWithKids {
        query = query.Where("good_with_kids = ?", true)
    }
    if filters.GoodWithDogs {
        query = query.Where("good_with_dogs = ?", true)
    }
    if filters.VaccinatedOnly {
        query = query.Where("is_vaccinated = ?", true)
    }
    if filters.EnergyLevel != "" {
        query = query.Where("energy_level = ?", filters.EnergyLevel)
    }

    err := query.Where("status = ?", domain.StatusAvailable).Find(&pets).Error
    return pets, err
}
```

### Impacto en la Arquitectura Global

**Cambios en Endpoints**

- **POST /pets**: Ahora recibe multipart/form-data en lugar de JSON puro
- **GET /pets**: Devuelve array de Pets con Images preloaded
- **GET /pets/{id}**: Devuelve Pet completo con Images y User
- **GET /matches/candidates**: Devuelve Pets con Images para swipe deck

**Cambios en el Flujo de Datos**

```
Rescatista en CreatePetScreen:
  ↓
  Selecciona 10 fotos + llena formulario con información médica
  ↓
  Envía FormData multipart a POST /pets
  ↓
PetHandler.Create():
  - Extrae archivos de multipart
  - Llama FileService.SaveMultipleImages()
  - Recibe URLs de MinIO/S3
  - Pasa ImageURLs[] a PetService.Create()
  ↓
PetService.Create():
  - Crea transacción
  - Inserta Pet (con primer ImageURL en PhotoURL)
  - Inserta array de PetImage (uno por URL)
  - Preload("Images") y devuelve
  ↓
Response: Pet con Images[] lleno
  ↓
Frontend:
  - Pet.fromJson() parsea array de imágenes
  - PetDetailScreen construye galería con PageView
  - ImageHelper renderiza cada imagen con error handling
```

### Consideraciones de Seguridad

**Validación de Archivos**

```go
func ValidateImageFile(file *multipart.FileHeader) error {
    // Validar tamaño
    if file.Size > 10*1024*1024 {  // 10 MB máximo
        return errors.New("archivo demasiado grande")
    }

    // Validar tipo MIME
    src, _ := file.Open()
    defer src.Close()

    buffer := make([]byte, 512)
    src.Read(buffer)

    contentType := http.DetectContentType(buffer)
    if !strings.Contains(contentType, "image") {
        return errors.New("archivo no es imagen")
    }

    return nil
}
```

**Prevención de Traversal Attacks**

```go
// INSEGURO: No usar nombres de archivo del usuario directamente
// filename := file.Filename  // ¡Peligro!

// SEGURO: Generar nombre único
filename := uuid.New().String() + filepath.Ext(file.Filename)
```

### Testing

**Mock PetService**

```go
type MockPetService struct {
    mock.Mock
}

func (m *MockPetService) Create(input CreatePetInput) (*domain.Pet, error) {
    args := m.Called(input)
    return args.Get(0).(*domain.Pet), args.Error(1)
}

// En tests:
func TestPetHandler_Create(t *testing.T) {
    mockService := new(MockPetService)
    mockService.On("Create", mock.Anything).Return(&domain.Pet{ID: 1}, nil)

    handler := &PetHandler{service: mockService}
    // ... assertions ...
}
```

### Notas Arquitectónicas

- **Backward Compatibility**: Campo PhotoURL mantenido. Si Images está vacío, sistemas anteriores todavía pueden usar PhotoURL.
- **Eager Loading Crítico**: Todos los servicios que devuelven Pet **deben** usar .Preload("Images"). Sin esto, la galería está vacía.
- **Transacciones Atómicas**: PetService.Create() usa transacción para garantizar consistencia: si PetImage falla, Pet se revierte.
- **Identificación de Portada**: IsCover flag en PetImage identifica la foto de portada. Frontend usa primera imagen por convención.
- **Límite de Imágenes**: 10 máximo por mascota. Evita uploads masivos. Limitación implementada en PetHandler.Create().

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

---

## COMPLETADO EN ETAPA 19: Filtro Espejo (Mirror Filter) en GetSwipeDeck

Etapa 19 introduce el **Filtro Espejo**, una capa crítica de privacidad para la doble identidad que impide que un usuario vea sus propias mascotas en el deck de búsqueda, incluso cuando usa su rol opuesto.

### El Problema

Con la doble identidad, un usuario es simultáneamente Adoptante y Rescatista. **Riesgo**: podría ver sus propias mascotas en GetSwipeDeck cuando cambia de rol, contaminando el flujo de matching.

### La Solución: Filtro por RUT

GetSwipeDeck() excluye mascotas del mismo RUT, independientemente del rol actual:

```go
func (s *MatchService) GetSwipeDeck(userID uint, lat, lon float64) ([]domain.Pet, error) {
    var currentUser domain.User
    if err := s.db.Select("run").First(&currentUser, userID).Error; err != nil {
        return nil, err
    }

    query := s.db.Table("pets p").
        Select("p.*").
        Joins("INNER JOIN users u ON p.user_id = u.id").
        Joins("LEFT JOIN matches m ON m.pet_id = p.id AND m.adopter_id = ?", userID).
        Where("m.id IS NULL").
        Where("p.status = ?", domain.StatusAvailable).
        Where("p.deleted_at IS NULL").
        Where("u.run <> ?", currentUser.Run)  // FILTRO ESPEJO: Excluye por RUT
    
    query = query.Order("p.created_at DESC").Limit(50)
    
    var pets []domain.Pet
    if err := query.Preload("Images").Find(&pets).Error; err != nil {
        return nil, err
    }
    return pets, nil
}
```

**Línea Clave**: `Where("u.run <> ?", currentUser.Run)` asegura que el usuario NUNCA ve sus propias mascotas.

### Garantía de Privacidad

| Escenario | RUT | Rol | ¿Ve propia mascota? | Razón |
|---|---|---|---|---|
| Adoptante en GetSwipeDeck | RUT-001 | adopter | NO | u.run <> RUT-001 |
| Rescatista en GetSwipeDeck | RUT-001 | rescuer | NO | u.run <> RUT-001 |
| Cambio a Rescatista (mismo RUT) | RUT-001 | rescuer | NO | u.run <> RUT-001 |
| Otro usuario busca | RUT-002 | any | SÍ | u.run <> RUT-002 ✓ |

### Integración con GET /pets/my

El Filtro Espejo es complementario a `GET /pets/my`:

- **GetSwipeDeck**: Ve MASCOTAS AJENAS (Filtro Espejo activo)
- **GET /pets/my**: Ve PROPIAS MASCOTAS (Sin filtro, control total)

Juntos garantizan:
- Usuario ve SUS mascotas en `/pets/my`
- Usuario ve mascotas AJENAS en `/swipedeck`
- Usuario NUNCA ve propias mascotas en `/swipedeck`
