# Etapa 17: Sistema de Justicia Integral - Denuncia, Investigación, Sentencia y Protección Pública

## Introducción

Etapa 17 transforma PAWS de una plataforma con reportes automáticos (Fase-8 con auto-ban) en un **sistema de justicia comunitario** donde administradores tienen discrecionalidad, la evidencia es inmutable, y el público tiene poder de verificación.

La pregunta fundamental que Etapa 17 responde: **¿Y si nos equivocamos?** Fase-8 automatizaba bans tras 3 reportes. Etapa 17 introduce administración humana, contexto completo (evidencia congelada), y categorías de delito para decisiones informadas.

## Los Cuatro Pilares de Etapa 17

### Pilar 1: Cimientos del Backend - Lógica de Justicia

Se extendieron los modelos de Fase-8 para soportar:

1. **Categorías de Reporte**: abuse, scam, spam, hate, other (vs "reason" genérico)
2. **Evidencia Congelada**: Chat inmutable como JSON en el momento del reporte
3. **Estados Discretos**: pending → resolved (ban) o pending → dismissed
4. **Auditoría**: Quién resolvió y cuándo (resolver_id, resolved_at)

```go
type Report struct {
    ID               uint
    ReporterID       uint      // Quién reporta
    ReportedID       uint      // Quién es reportado
    MatchID          uint      // El chat donde ocurrió (contexto)
    Category         string    // "abuse" | "scam" | "spam" | "hate" | "other"
    Description      string    // Descripción del reportador
    EvidenceSnapshot string    // JSON del chat congelado
    Status           string    // "pending" | "resolved" | "dismissed"
    ResolvedAt       *time.Time
    ResolverID       *uint     // Admin que resolvió
    Reporter         User      // Relación
    Reported         User      // Relación
}

type BlacklistEntry struct {
    ID   uint
    Run  string `gorm:"uniqueIndex"` // RUT chileno único
    Name string                      // Nombre al momento del ban
    Reason string                    // Razón pública (e.g., "Maltrato Animal")
}
```

### Pilar 2: Experiencia del Denunciante - El Botón de Pánico

Usuarios ahora pueden reportar desde ChatScreen sin alertar al reportado:

```dart
// En ChatScreen, PopupMenuButton
const PopupMenuItem(
  value: 'report',
  child: Row(
    children: [
      Icon(Icons.flag_outlined, color: Colors.orange),
      SizedBox(width: 8),
      Text("Reportar usuario"),
    ],
  ),
),

// Se abre diálogo con:
// - Dropdown de categorías
// - Campo de descripción validado
// - Envío silencioso (sin notificación al reportado)
```

Características críticas:

- **Anonimato**: El reportado nunca sabe quién lo reportó
- **Silencio**: No hay notificación que alerte al reportado
- **Validación**: Descripción requerida (no reportes vacíos)
- **Confirmación Suave**: Solo SnackBar para el reportador

### Pilar 3: Centro de Resolución - Admin Dashboard

Panel exclusivo para admins (role=admin) con:

1. **Lista de Reportes**: Cards mostrando categoría, nombres, descripción
2. **Visor de Evidencia**: Chat congelado reutilizando ChatBubble
3. **Decisiones Binarias**: Desestimar o BAN
4. **Blacklist Pública Opcional**: Checkbox para hacer el ban público

```dart
// AdminDashboardScreen muestra:
- ListView de Reports
- Cada Card toca → ReportDetailScreen
- Visor de chat congelado (evidenceMessages)
- Botones: "Desestimar" vs "EJECUTAR BAN"
- Si BAN: Dialog con checkbox "Agregar a Blacklist Pública"
```

El visor de evidencia es sofisticado:

```dart
// En ReportDetailScreen
ListView.builder(
  itemCount: report.evidenceMessages!.length,
  itemBuilder: (context, index) {
    final msg = report.evidenceMessages![index];
    final isReporter = msg.senderId == report.reporterId;
    return ChatBubble(message: msg, isMe: isReporter);
  },
)
```

Esto reutiliza el widget ChatBubble del chat normal, mostrando el historial exactamente como ocurrió.

### Pilar 4: Escudo Público - Consulta de Antecedentes

Nueva pantalla accesible desde LoginScreen y ProfileScreen:

```dart
// BlacklistSearchScreen
- Campo RUT con formateo automático: "12.345.678-9"
- Validación Módulo 11 en tiempo real
- Búsqueda pública (GET /blacklist/search?rut=...)
- Resultados:
  * Tarjeta Roja (Peligro): Nombre, razón, fecha
  * Tarjeta Verde (Sin antecedentes): Ícono check, "Limpio"
```

El endpoint es **público** (sin JWT requerido):

```go
GET /blacklist/search?rut=12.345.678-9
// Respuesta: {found: true, name, reason, date}
// o: {found: false, message: "Sin antecedentes"}
```

## Arquitectura Detallada

### Transacción Atómica: Ban + Blacklist

El punto más crítico de Etapa 17 es la atomicidad:

```go
func (s *ReportService) ResolveReport(
    adminID, reportID uint,
    action string,        // "ban" o "dismiss"
    publicBlacklist bool,
) error {
    return s.db.Transaction(func(tx *gorm.DB) error {
        var report Report
        if err := tx.First(&report, reportID).Error; err != nil {
            return err
        }

        // Si es ban, ejecutar transacción completa
        if action == "ban" {
            // 1. Marcar usuario como baneado
            if err := tx.Model(&User{}).Where("id = ?", report.ReportedID).
                Update("is_banned", true).Error; err != nil {
                return err
            }

            // 2. Opcionalmente, agregar a blacklist pública
            if publicBlacklist {
                var user User
                if err := tx.First(&user, report.ReportedID).Error; err != nil {
                    return err
                }

                entry := BlacklistEntry{
                    Run:    user.Run,
                    Name:   user.Name,
                    Reason: report.Category, // Categoría como razón pública
                }
                if err := tx.Create(&entry).Error; err != nil {
                    return err
                }
            }
        }

        // 3. Marcar reporte como resuelto
        now := time.Now()
        if err := tx.Model(&report).Updates(map[string]interface{}{
            "status":       action,
            "resolved_at":  now,
            "resolver_id":  adminID,
        }).Error; err != nil {
            return err
        }

        return nil
    })
}
```

**Si algo falla** (DB corrupta, permisos insuficientes), toda la transacción revierte. No hay estados intermedios.

### Categorías de Reporte

| Código  | Traducción Frontend      | Contexto                              | Acción Típica            |
| ------- | ------------------------ | ------------------------------------- | ------------------------ |
| `abuse` | Maltrato Animal          | Agresión, amenazas, lenguaje ofensivo | Ban + Blacklist          |
| `scam`  | Estafa / Fraude          | Dinero falso, promesas incumplidas    | Ban + Blacklist          |
| `spam`  | Spam / Publicidad        | Anuncios repetitivos, links malos     | Ban (opcional Blacklist) |
| `hate`  | Lenguaje Ofensivo / Odio | Discriminación, racismo               | Ban + Blacklist          |
| `other` | Otro                     | Catch-all                             | Caso por caso            |

### Validación Módulo 11 - RUT Chileno

Implementado en BlacklistSearchScreen para prevenir búsquedas con RUTs malformados:

```dart
bool _isValidRut(String rut) {
    String clean = rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
    if (clean.length < 8) return false;

    try {
        int number = int.parse(clean.substring(0, clean.length - 1));
        String verifier = clean[clean.length - 1];

        int m = 0, s = 0;
        while (number > 0) {
            s += number % 10 * (m % 6 + 2);
            number ~/= 10;
            m++;
        }

        int dv = (11 - (s % 11)) % 11;
        String expectedVerifier = dv == 10 ? 'K' : dv.toString();

        return verifier == expectedVerifier;
    } catch (e) {
        return false;
    }
}
```

Si alguien escribe `12.345.678-0` pero el dígito correcto es `9`, el sistema rechaza la búsqueda.

### Silencio Operativo - Protección del Denunciante

Etapa 17 implementa "silencio operativo":

1. **Al reportar**: Usuario reportado **NO** recibe notificación
2. **Mientras se investiga**: Admin revisa silenciosamente
3. **Al bannear**: Usuario solo descubre al intentar loguearse ("Tu cuenta ha sido suspendida")
4. **En Blacklist**: Nombre es público, pero identidad del denunciante permanece oculta

Esto es **crítico** en abuso doméstico o situaciones donde represalia es riesgo.

### Evidencia Congelada - Inmutabilidad Legal

Cuando se crea un reporte, el chat completo se congela en JSON:

```json
{
  "id": 42,
  "evidence": [
    {
      "id": 1,
      "sender_id": 123,
      "sender_name": "Juan",
      "content": "¿Cuánto cuesta tu perro?",
      "timestamp": "2024-01-15T10:30:00Z"
    },
    {
      "id": 2,
      "sender_id": 456,
      "sender_name": "María",
      "content": "Depósito anticipado de $5000",
      "timestamp": "2024-01-15T10:31:15Z"
    }
  ]
}
```

Aunque el usuario reportado borre la conversación después, esta prueba permanece inmutable para investigación.

## Endpoints - Etapa 17

### Administrativos (Requieren role="admin")

```go
GET /admin/reports
// Lista de reportes pendientes
// Respuesta: []Report con Reporter y Reported preloaded
// Paginación: ?page=1&limit=20

GET /admin/reports/:id
// Detalle de reporte específico con evidenceMessages
// Respuesta: Report con chat congelado

POST /admin/reports/:id/resolve
// Ejecutar sentencia
// Body: {action: "ban"|"dismiss", public_blacklist: bool}
// Respuesta: {success: true} o error
```

### Públicos (SIN autenticación)

```go
GET /blacklist/search?rut=12.345.678-9
// Búsqueda pública de antecedentes
// Respuesta: {found: bool, name?, reason?, date?}
// O: {found: false, message: "Sin antecedentes"}
```

### Usuario (Requieren JWT)

```go
POST /api/v1/report
// Crear reporte
// Body: {reported_id, match_id, category, description}
// Respuesta: {success: true}
```

## Flujo Completo - De Reporte a Justicia

```
1. REPORTE
   ChatScreen → "Reportar Usuario" → Diálogo
   → POST /api/v1/report
   → ReportService.CreateReport()
   → Report.Status = "pending"
   → NO notificación a reportado

2. INVESTIGACIÓN
   Admin → AdminDashboardScreen
   → GET /admin/reports
   → Toca reporte → ReportDetailScreen
   → Ve evidencia (chat congelado)
   → Lee categoría, descripción

3. SENTENCIA
   Admin decide: "Desestimar" o "BAN"

   Si Desestimar:
   → POST /admin/reports/:id/resolve {action: "dismiss"}
   → Report.Status = "dismiss"
   → Usuario reportado sigue activo

   Si BAN:
   → Dialog: "¿Blacklist pública?"
   → POST /admin/reports/:id/resolve {action: "ban", public_blacklist: true}
   → En TRANSACTION:
     * User.is_banned = true
     * BlacklistEntry creada (si public_blacklist=true)
     * Report.Status = "ban", resolved_at = now, resolver_id = admin.id
   → TODO ATÓMICO

4. PROTECCIÓN PÚBLICA
   Usuario nuevo en LoginScreen
   → "¿Verificar antecedentes?" link
   → BlacklistSearchScreen
   → GET /blacklist/search?rut=12345678-9
   → Si encontrado: Tarjeta Roja con "PELIGRO"
   → Si no: Tarjeta Verde "Sin antecedentes"
```

## Impacto en la Comunidad

**Antes (Fase-8)**:

- Auto-ban tras 3 reportes (¿y si todos reportaban mentiras?)
- Contexto invisible (admin solo veía nombres)
- Comunidad sin forma de verificar

**Después (Etapa 17)**:

- Admin controla justicia con contexto (evidencia congelada)
- Comunidad verifica RUTs antes de confiar
- Baneados públicos actúan como disuasión
- Adopciones más seguras, estafadores identificados

## Testing Crítico - Etapa 17

Puntos esenciales para validar:

1. **Atomicidad**: Si DB falla durante ban, TODO revierte (no baneado-sin-blacklist)
2. **Silencio**: POST /report NO envía notificación al reportado
3. **Módulo 11**: RUT `12.345.678-0` rechazado si dígito correcto es `9`
4. **Autenticación Admin**: GET /admin/reports retorna 401 si role != "admin"
5. **Evidencia**: Chat congelado es idéntico al historial original

## Relación con Etapas Futuras

Etapa 17 es la fundación de **auto-regulación comunitaria**. Futuras etapas podrían incluir:

- **Etapa 18**: Apelaciones - Baneados pueden apelar
- **Etapa 19**: Transparencia - Reportador ve estado de su reporte
- **Etapa 20**: Comité - Múltiples admins aprueban bans graves

## Conclusión

Etapa 17 convierte PAWS de una plataforma **permisiva con reportes automáticos** en una **comunidad responsable con justicia administrada**. Cada reporte es investigado, cada decisión es documentada, y cada comunidad tiene poder de verificación.

El sistema responde la pregunta fundamental: cuando alguien es baneado, ¿qué pasó? La respuesta: **Aquí está el chat congelado. Aquí está la decisión del admin. Y aquí está el RUT en la blacklist pública si fue grave.**

La justicia no es ciega en PAWS. Tiene contexto, tiene discrecionalidad, y tiene comunidad de testigos.
