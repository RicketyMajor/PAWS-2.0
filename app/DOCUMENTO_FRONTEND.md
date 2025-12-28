# Documentación Exhaustiva - PAWS Frontend (Flutter)

## Tabla de Contenidos

1. [Resumen General](#resumen-general)
2. [Estructura del Proyecto](#estructura-del-proyecto)
3. [Dependencias y Librerías](#dependencias-y-librerías)
4. [Arquitectura General](#arquitectura-general)
5. [Carpeta Core](#carpeta-core)
6. [Feature: Autenticación (Auth)](#feature-autenticación-auth)
7. [Feature: Mascotas y Matching (Pets)](#feature-mascotas-y-matching-pets)
8. [Feature: Chat](#feature-chat)
9. [Flujo de Conexiones](#flujo-de-conexiones)
10. [Flujos de Usuario](#flujos-de-usuario)
11. [Detalles Técnicos de Implementación](#detalles-técnicos-de-implementación)

---

## Resumen General

**Proyecto:** PAWS App  
**Tipo:** Aplicación Mobile (Flutter)  
**Propósito:** Plataforma de matching entre mascotas en adopción y adoptantes  
**Versión Flutter:** SDK ^3.10.4  
**Plataformas Soportadas:** Android, iOS, Windows, Linux, macOS (web no está configurado aún)

PAWS es una aplicación de dating estilo Tinder para mascotas. Permite a los adoptantes (usuarios) hacer swipe en mascotas disponibles para adopción, conectarse con refugios/criadores, y conversar con ellos a través de chat en tiempo real.

---

## Estructura del Proyecto

```
paws_app/
├── lib/                                   # Código fuente principal de la app
│   ├── main.dart                          # Punto de entrada de la aplicación
│   ├── core/                              # Utilidades compartidas globales
│   │   ├── constants/
│   │   │   └── api_constants.dart         # URLs base y endpoints de API
│   │   ├── errors/                        # [CARPETA VACÍA] Para manejo de errores futuro
│   │   ├── router/                        # [CARPETA VACÍA] Para navegación futura (Go Router)
│   │   └── theme/                         # [CARPETA VACÍA] Para temas globales
│   └── features/                          # Funcionalidades principales (estructura Clean Architecture)
│       ├── auth/                          # Módulo de Autenticación
│       │   ├── data/
│       │   │   └── auth_repository.dart   # Comunicación HTTP con backend (Login, Register, OTP)
│       │   ├── domain/                    # [VACÍO] Modelos de entidad (no implementado)
│       │   └── presentation/
│       │       ├── bloc/
│       │       │   └── login_bloc.dart    # Estado y lógica de Login (BLoC)
│       │       └── screens/
│       │           ├── login_screen.dart    # Pantalla de Login
│       │           ├── register_screen.dart # Pantalla de Registro
│       │           └── otp_screen.dart      # Pantalla de Verificación OTP
│       ├── pets/                          # Módulo de Matching y Mascotas
│       │   ├── data/
│       │   │   └── pets_repository.dart   # Comunicación HTTP (Obtener mascotas, Swipes)
│       │   ├── domain/
│       │   │   └── pet_model.dart         # Modelo de Mascota (Pet)
│       │   └── presentation/
│       │       ├── bloc/
│       │       │   └── pets_bloc.dart     # Estado y lógica de Matching (BLoC)
│       │       └── screens/
│       │           └── match_screen.dart  # Pantalla principal de Swipes
│       └── chat/                          # Módulo de Chat en Tiempo Real
│           ├── data/
│           │   └── chat_repository.dart   # HTTP (historial) + WebSocket (mensajes)
│           ├── domain/
│           │   └── message_model.dart     # Modelo de Mensaje (ChatMessage)
│           └── presentation/
│               ├── bloc/
│               │   └── chat_bloc.dart     # Estado y lógica de Chat (BLoC)
│               └── screens/
│                   └── chat_screen.dart   # Pantalla de Chat
├── android/                               # Código nativo Android
├── ios/                                   # Código nativo iOS
├── windows/                               # Código nativo Windows
├── linux/                                 # Código nativo Linux
├── macos/                                 # Código nativo macOS
├── web/                                   # [NO IMPLEMENTADO] Código web
├── test/                                  # Pruebas unitarias
├── pubspec.yaml                           # Dependencias y configuración del proyecto
├── analysis_options.yaml                  # Opciones de análisis de código
├── README.md                              # Documentación base (poco contenido)
└── paws_app.iml                           # Archivo de proyecto IDE
```

---

## Dependencias y Librerías

### Dependencias Principales del pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter

  # UI & Iconografía
  cupertino_icons: ^1.0.8 # Iconos estilo iOS
  google_fonts: ^6.3.3 # Fuentes personalizadas de Google
  lottie: ^3.1.0 # Animaciones JSON (ej: check de éxito)

  # Networking
  dio: ^5.9.0 # Cliente HTTP robusto
  web_socket_channel: ^3.0.3 # WebSocket para chat en tiempo real

  # State Management
  flutter_bloc: ^9.1.1 # BLoC para gestión de estado
  equatable: ^2.0.7 # Comparación de objetos
  provider: ^6.1.1 # Inyección de dependencias (alternativa a get_it)

  # Autenticación
  jwt_decoder: ^2.0.1 # Decodificar tokens JWT
  flutter_secure_storage: ^10.0.0 # Almacenamiento seguro (Keychain/Keystore)

  # Navegación
  go_router: ^17.0.1 # Routing declarativo (NO IMPLEMENTADO AÚN)

  # Características
  flutter_card_swiper: ^7.2.0 # Swiper de cartas tipo Tinder
  cached_network_image: ^3.4.1 # Cache de imágenes de red
  image_picker: ^1.2.1 # Selector de fotos para verificación
  geolocator: ^10.1.0 # Obtener ubicación GPS del usuario
  shared_preferences: ^2.5.4 # Almacenamiento local simple
  get_it: ^7.6.0 # Inyección de dependencias
```

### Estructura de Dependencias Explicada

- **flutter_bloc**: Gestiona el estado de la aplicación siguiendo el patrón BLoC (Business Logic Component)
- **dio**: Para todas las llamadas HTTP al backend (REST API)
- **web_socket_channel**: Para comunicación en tiempo real en el chat
- **flutter_secure_storage**: Almacena el JWT de forma segura (no en SharedPreferences simple)
- **flutter_card_swiper**: Crea la interfaz de swipe similar a Tinder
- **image_picker + dio**: Para capturar/seleccionar fotos de identidad en registro
- **geolocator**: Para obtener coordenadas del usuario (matching por ubicación)
- **jwt_decoder**: Extrae datos del token sin validar firma (para obtener user_id)

---

## Arquitectura General

### Patrón de Arquitectura: Clean Architecture + BLoC

```
Presentation Layer (UI)
        ↓
  BLoC Layer (Lógica)
        ↓
  Repository Layer (Datos)
        ↓
API/Base de Datos
```

### Flujo de Datos en BLoC

```
User Interaction (tap, texto)
    → Screen emite Event al BLoC
    → BLoC procesa el Event
    → BLoC emite un State
    → Screen reacciona al State (muestra UI)
```

**Ejemplo Concreto:** Usuario presiona botón Login

```
LoginScreen → LoginButtonPressed(email, password)
    → LoginBloc.on<LoginButtonPressed>()
    → AuthRepository.login()
    → Backend responde
    → Emite LoginSuccess
    → LoginScreen navega a MatchScreen
```

### Inyección de Dependencias

En `main.dart`, se usa `MultiRepositoryProvider` para inyectar los Repositorios en toda la aplicación:

```dart
MultiRepositoryProvider(
  providers: [
    RepositoryProvider(create: (context) => AuthRepository()),
    RepositoryProvider(create: (context) => PetsRepository()),
    RepositoryProvider(create: (context) => ChatRepository()),
  ],
  child: MaterialApp(...)
)
```

Esto significa que cualquier widget puede acceder a estos repositorios con:

```dart
context.read<AuthRepository>()
context.read<PetsRepository>()
context.read<ChatRepository>()
```

---

## Carpeta Core

### 1. api_constants.dart

**Función:** Centraliza todas las URLs y endpoints de la API

**Contenido:**

```dart
class ApiConstants {
  static const String baseUrl = 'http://10.0.2.2:8080/api/v1';  // IP del Docker local (Emulador Android)
  static const String wsUrl = 'ws://10.0.2.2:8080/api/v1';      // WebSocket base URL

  // Endpoints de Autenticación
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verifyOtp = '/auth/otp/verify';

  // Endpoints de Matching
  static const String swipeDeck = '/matches/candidates';
  static const String swipeAction = '/matches/swipe';
}
```

**Nota Importante:**

- `10.0.2.2` es una IP especial para emulador Android que representa la máquina anfitriona
- Para dispositivo físico, cambiar por la IP local (ej: `192.168.1.15`)
- Las URLs se usan como: `${ApiConstants.baseUrl}${ApiConstants.login}`

### 2. Carpetas Vacías (Para Expansión Futura)

| Carpeta        | Propósito Futuro                                                             |
| -------------- | ---------------------------------------------------------------------------- |
| `core/errors/` | Clases de excepciones personalizadas (AuthException, NetworkException, etc.) |
| `core/router/` | Configuración de GoRouter para navegación más avanzada                       |
| `core/theme/`  | Configuración centralizada de temas (colores, tipografía, estilos)           |

---

## Feature: Autenticación (Auth)

### Responsabilidad

Maneja el registro, login y verificación OTP de usuarios.

### Arquivos Principales

#### 1. auth_repository.dart

**Clase:** `AuthRepository`

**Responsabilidades:**

- Comunicación HTTP con endpoints de autenticación
- Almacenamiento seguro del JWT en el dispositivo
- Logging de peticiones (debug)

**Métodos Principales:**

```dart
Future<void> login(String email, String password)
```

- Envía credenciales al backend `/auth/login`
- Si es exitoso (200 OK), recibe un JWT y lo guarda en FlutterSecureStorage
- Lanza Exception si hay error

```dart
Future<void> register({
  required String email,
  required String password,
  required String name,
  required String run,
  String role = 'adopter'
})
```

- Registra un nuevo usuario en `/auth/register`
- Parámetros:
  - `email`: Correo del usuario
  - `password`: Contraseña
  - `name`: Nombre completo
  - `run`: RUN chileno (Rol Único Nacional) o DNI
  - `role`: Tipo de usuario ('adopter' = adoptante, podría haber 'shelter')
- Trigger: Backend envía email con código OTP vía RabbitMQ

```dart
Future<bool> verifyOtp(String email, String code)
```

- Verifica el código OTP en `/auth/otp/verify`
- Retorna `true` si el código es válido
- Usado después del registro para confirmar email

**Detalles Técnicos:**

- Usa `Dio` con timeout de 10 segundos
- Incluye `LogInterceptor` para debugging (registra todos los requests/responses)
- Maneja `DioException` y extrae mensajes de error del servidor
- Almacenamiento con `FlutterSecureStorage` (más seguro que SharedPreferences)

#### 2. login_bloc.dart

**Clases:**

```dart
abstract class LoginEvent extends Equatable {}
  └── LoginButtonPressed(email, password)
```

Evento disparado cuando el usuario presiona el botón Login

```dart
abstract class LoginState extends Equatable {}
  ├── LoginInitial
  ├── LoginLoading
  ├── LoginSuccess
  └── LoginFailure(error)
```

Estados que representa el flujo de login

```dart
class LoginBloc extends Bloc<LoginEvent, LoginState>
```

**Lógica:**

```dart
on<LoginButtonPressed>((event, emit) async {
  emit(LoginLoading());                           // Muestra spinner
  try {
    await authRepository.login(...);              // Intenta login
    emit(LoginSuccess());                         // Si funciona
  } catch (e) {
    emit(LoginFailure(error: e.toString()));     // Si falla
  }
})
```

#### 3. login_screen.dart

**Clase:** `LoginScreen` (StatelessWidget)

**Responsabilidades:**

- UI del Login
- Provee LoginBloc al árbol de widgets

**Elemento:** `_LoginForm` (StatefulWidget)

**Componentes:**

- Campo Email (TextEditingController)
- Campo Contraseña (TextEditingController con toggle de visibilidad)
- Botón Login
- Link "¿No tienes cuenta?" → Navega a RegisterScreen

**Listeners (BlocListener):**

- Si `LoginFailure`: Muestra SnackBar rojo con error
- Si `LoginSuccess`: Muestra SnackBar verde y navega a MatchScreen (borrando historial)

**Navegación:**

```dart
Navigator.pushAndRemoveUntil(
  context,
  MaterialPageRoute(builder: (context) => const MatchScreen()),
  (route) => false,  // Borra todo el historial anterior
);
```

#### 4. register_screen.dart

**Clase:** `RegisterScreen` (StatefulWidget)

**Responsabilidades:**

- Registro de nuevos usuarios
- Captura de datos y documento de identidad

**Campos de Input:**

- Nombre Completo (TextField)
- Email (TextField)
- Contraseña (TextField obscurecido)
- RUN/DNI (TextField)
- Botón "Escanear Identidad" (integra con image_picker)

**Funciones Principales:**

```dart
Future<void> _submitRegister()
```

1. Valida que campos no estén vacíos
2. Llama a `AuthRepository.register()`
3. Si éxito: Muestra SnackBar azul y navega a OTPScreen
4. Si falla: Muestra error en SnackBar rojo

```dart
Future<void> _scanIdentity()
```

1. Abre galería (image_picker)
2. Convierte imagen a FormData (multipart)
3. Envía a `/verification/verify` (backend Evil PAWS)
4. Backend extrae RUN de la imagen
5. Si éxito: Auto-rellena campo RUN

**Flujo de Registro:**

```
RegisterScreen → _submitRegister()
  → AuthRepository.register()
  → Backend envía email con OTP
  → OTPScreen
```

#### 5. otp_screen.dart

**Clase:** `OTPScreen` (StatefulWidget)

**Parámetro Constructor:**

- `email`: Correo del usuario registrado

**Responsabilidades:**

- Solicita código OTP (6 dígitos)
- Verifica en backend
- Entrada directa a la app (MatchScreen)

**Componentes:**

- Mensaje mostrando el email
- TextField para código (máx 6 caracteres, números, centrado, grandes)
- Botón Verificar

**Función Principal:**

```dart
void _verify()
```

1. Obtiene código del TextField
2. Llama a `AuthRepository.verifyOtp(email, code)`
3. Si `true`:
   - Muestra SnackBar verde "¡Cuenta verificada!"
   - Navega a MatchScreen (borrando historial)
4. Si `false`:
   - Muestra SnackBar rojo "Código incorrecto"

**Nota Importante:** Después de OTP exitoso, usuario entra directo a MatchScreen (no vuelve a Login)

---

## Feature: Mascotas y Matching (Pets)

### Responsabilidad

Muestra mascotas disponibles para adopción y registra el interés del usuario (swipes).

### Archivos Principales

#### 1. pet_model.dart

**Clase:** `Pet`

**Atributos:**

```dart
final int id;              // ID único de la mascota
final String name;         // Nombre de la mascota
final String type;         // Tipo (perro, gato, etc.)
final String breed;        // Raza
final int age;            // Edad en años
final String description; // Descripción/bio
final String? imageUrl;   // URL de imagen
final bool goodWithKids;  // Compatible con niños
final bool goodWithDogs;  // Compatible con otros perros
final bool requiresYard;  // Requiere patio
```

**Factory Constructor:**

```dart
Pet.fromJson(Map<String, dynamic> json)
```

Convierte JSON del backend a objeto Pet

**Funciones Auxiliares (dentro de fromJson):**

- `parseInt()`: Convierte dinámicamente int/String → int
- `parseBool()`: Convierte dinámicamente bool/String → bool

**Ejemplo de JSON esperado del backend:**

```json
{
  "id": 1,
  "name": "Rufus",
  "type": "Perro",
  "breed": "Golden Retriever",
  "age": 3,
  "description": "Perro amigable y juguetón",
  "image_url": "https://...",
  "good_with_kids": true,
  "good_with_dogs": true,
  "requires_yard": true
}
```

#### 2. pets_repository.dart

**Clase:** `PetsRepository`

**Responsabilidades:**

- Obtener lista de mascotas (algoritmo inteligente de matching)
- Registrar swipes (like/dislike)

**Métodos Principales:**

```dart
Future<List<Pet>> getSwipeDeck()
```

- Endpoint: `GET /matches/candidates`
- Headers: Authorization Bearer Token
- Retorna: Lista de mascotas cercanas/compatibles
- Error Handling: Diferencia entre JSON error y texto plano de panic

```dart
Future<void> swipePet({required int petId, required bool isLike})
```

- Endpoint: `POST /matches/swipe`
- Body: `{ "pet_id": id, "is_like": true/false }`
- No lanza excepción en caso de error (para no interrumpir UI)

**Nota de Seguridad:**
El token JWT se obtiene automáticamente de FlutterSecureStorage en cada request

#### 3. pets_bloc.dart

**Eventos:**

```dart
class LoadSwipeDeck extends PetsEvent
```

Carga el mazo inicial de mascotas

```dart
class SwipePetEvent extends PetsEvent {
  final int petId;
  final bool isLike;
}
```

Usuario hizo swipe (left=dislike, right=like)

**Estados:**

```dart
abstract class PetsState extends Equatable {}
  ├── PetsInitial              // Inicio
  ├── PetsLoading              // Cargando mascotas
  ├── PetsLoaded(List<Pet>)    // Mascotas listas
  └── PetsError(String)        // Error en carga
```

**Lógica del BLoC:**

```dart
on<LoadSwipeDeck>((event, emit) async {
  emit(PetsLoading());
  final pets = await repository.getSwipeDeck();  // Obtiene lista
  emit(PetsLoaded(pets));                        // Emite mascotas
})

on<SwipePetEvent>((event, emit) async {
  if (state is PetsLoaded) {
    // Envía swipe al backend SIN esperar respuesta (optimista)
    repository.swipePet(petId: event.petId, isLike: event.isLike);
    // La UI se actualiza visualmente vía flutter_card_swiper
    // No removemos de la lista localmente
  }
})
```

**Nota:** El BLoC es "optimista" - no espera confirmación del servidor para actualizar UI

#### 4. match_screen.dart

**Clase:** `MatchScreen` (StatelessWidget)

**Estructura:**

```
MatchScreen
  └── BlocProvider<PetsBloc>
      └── Scaffold
          ├── AppBar (título "PAWS")
          └── MatchView (BlocBuilder)
```

**Responsabilidades:**

- Muestra AppBar con título
- Provee PetsBloc al árbol
- Dispara evento `LoadSwipeDeck()` al crear el BLoC

**MatchView (StatelessWidget):**

Responde a diferentes estados:

1. **PetsLoading:**

   - Muestra CircularProgressIndicator pink

2. **PetsError:**

   - Muestra ícono de error
   - Mensaje: "Algo salió mal: [error]"
   - Botón "Reintentar" dispara LoadSwipeDeck()

3. **PetsLoaded (vacío):**

   - Muestra ícono de mascota
   - Mensaje: "No hay mascotas nuevas cerca de ti"
   - Submensaje: "¡Vuelve a intentar más tarde!"

4. **PetsLoaded (con mascotas):**
   - Usa `FlutterCardSwiper` (librería de swipe tipo Tinder)
   - Por cada mascota muestra:
     - Imagen
     - Nombre
     - Raza
     - Edad
     - Descripción
     - Badges (bueno con niños, perros, etc.)
   - Left swipe → dislike (`SwipePetEvent(id, false)`)
   - Right swipe → like (`SwipePetEvent(id, true)`)

**Construcción de Tarjeta:**

```dart
ClipRRect(
  borderRadius: BorderRadius.circular(16),
  child: Stack(
    children: [
      // Imagen de fondo
      CachedNetworkImage(
        imageUrl: pet.imageUrl ?? '',
        fit: BoxFit.cover,
      ),
      // Overlay gradiente oscuro
      // Información en la base (nombre, raza, edad)
    ]
  )
)
```

---

## Feature: Chat

### Responsabilidad

Chat en tiempo real entre usuarios que hicieron match usando WebSocket.

### Archivos Principales

#### 1. message_model.dart

**Clase:** `ChatMessage`

**Atributos:**

```dart
final int id;              // ID del mensaje
final int matchId;         // ID del match
final int senderId;        // ID del usuario que envía
final String content;      // Contenido del mensaje
final bool isRead;        // Leído?
final DateTime createdAt; // Timestamp
final bool isMe;          // ¿Es mío? (auxiliar para UI)
```

**Factory Constructor:**

```dart
ChatMessage.fromJson(Map<String, dynamic> json, int currentUserId)
```

Convierte JSON a objeto y determina `isMe` comparando senderId

**Ejemplo JSON esperado:**

```json
{
  "id": 1,
  "match_id": 5,
  "sender_id": 10,
  "content": "Hola, me interesa adoptar",
  "is_read": false,
  "created_at": "2024-01-15T10:30:00Z"
}
```

#### 2. chat_repository.dart

**Clase:** `ChatRepository`

**Atributos Privados:**

- `_dio`: Cliente HTTP (para historial)
- `_storage`: Almacenamiento seguro (para token)
- `_channel`: Conexión WebSocket actual

**Métodos Principales:**

```dart
Future<int> _getMyUserId()
```

Privado. Decodifica JWT para obtener user_id desde token (`sub` claim)

```dart
Future<List<ChatMessage>> getHistory(int matchId)
```

- Endpoint: `GET /matches/:id/messages`
- Headers: Authorization Bearer Token
- Retorna: Historial de mensajes (carga inicial)
- Ordena por fecha más antigua

```dart
Future<Stream<dynamic>> connectToChat()
```

- Conecta WebSocket a `ws://[baseUrl]/ws`
- Pasa token en headers del handshake
- Retorna Stream que recibe mensajes en tiempo real
- Nota: Backend envía solo el contenido del mensaje (string)

```dart
void sendMessage(int matchId, String content)
```

- Envía JSON por WebSocket:
  ```json
  { "match_id": 5, "content": "Hola!" }
  ```

```dart
void disconnect()
```

- Cierra la conexión WebSocket

**Consideraciones Técnicas:**

- El WebSocket espera que el frontend envíe JSON con structure específica
- El backend podría devolver solo texto plano o JSON completo (actualmente ajustado para texto)
- La conexión es persistente (una por usuario activo)

#### 3. chat_bloc.dart

**Eventos:**

```dart
class InitChat extends ChatEvent {
  final int matchId;
}
```

Inicializa chat (carga historial + conecta WS)

```dart
class SendMessageEvent extends ChatEvent {
  final String content;
}
```

Usuario envía mensaje

```dart
class _ReceiveMessageEvent extends ChatEvent {
  final ChatMessage message;
}
```

Evento interno: llega mensaje por WebSocket

**Estados:**

```dart
abstract class ChatState extends Equatable {}
  ├── ChatLoading
  ├── ChatLoaded(messages, matchId)
  ├── ChatError(error)
```

**Lógica del BLoC:**

```dart
on<InitChat>((event, emit) async {
  _currentMatchId = event.matchId;
  emit(ChatLoading());

  try {
    // 1. Cargar historial
    final history = await repository.getHistory(event.matchId);
    emit(ChatLoaded(messages: history, matchId: event.matchId));

    // 2. Conectar WebSocket
    final stream = await repository.connectToChat();

    // 3. Escuchar mensajes entrantes
    _wsSubscription?.cancel();
    _wsSubscription = stream.listen((data) {
      // Cuando llega mensaje del servidor
      final newMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch,
        matchId: _currentMatchId,
        senderId: 0,  // No sabemos sender exacto de WS
        content: data.toString(),
        isRead: false,
        createdAt: DateTime.now(),
        isMe: false,  // Asumimos que lo que llega es del otro
      );
      add(_ReceiveMessageEvent(newMsg));
    });
  } catch (e) {
    emit(ChatError(e.toString()));
  }
})

on<SendMessageEvent>((event, emit) async {
  if (state is ChatLoaded) {
    final currentState = state as ChatLoaded;

    // Crear mensaje local (para mostrar inmediatamente)
    final newMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch,
      matchId: _currentMatchId,
      senderId: _currentUserId,  // Nuestro ID
      content: event.content,
      isRead: true,
      createdAt: DateTime.now(),
      isMe: true,
    );

    // Actualizar lista localmente (optimista)
    final updatedMessages = [...currentState.messages, newMsg];
    emit(ChatLoaded(messages: updatedMessages, matchId: _currentMatchId));

    // Enviar al servidor (background)
    repository.sendMessage(_currentMatchId, event.content);
  }
})

on<_ReceiveMessageEvent>((event, emit) async {
  if (state is ChatLoaded) {
    final currentState = state as ChatLoaded;
    final updatedMessages = [...currentState.messages, event.message];
    emit(ChatLoaded(messages: updatedMessages, matchId: _currentMatchId));
  }
})
```

#### 4. chat_screen.dart

**Clase:** `ChatScreen` (StatelessWidget)

**Parámetros Constructor:**

```dart
final int matchId;      // ID del match
final String peerName;  // Nombre del usuario con quien se habla
```

**Estructura:**

```
ChatScreen
  └── BlocProvider<ChatBloc>
      └── Scaffold
          ├── AppBar (muestra peerName)
          └── Column
              ├── Expanded (lista de mensajes)
              └── _ChatInput (campo de entrada)
```

**Responsabilidades:**

- Dispara `InitChat(matchId)` al crear BLoC
- Muestra historial y mensajes nuevos
- Proporciona input para enviar mensajes

**Secciones:**

1. **Área de Mensajes (ListView):**

   - Responde a estados:

     - Loading: CircularProgressIndicator
     - ChatLoaded: Lista con mensajes
     - ChatError: Muestra error

   - **Construcción de Burbuja:**
     ```dart
     _buildMessageBubble(ChatMessage msg)
     ```
     - Alineación: derecha si `msg.isMe`, izquierda si no
     - Color: deep purple si es mío, gris si es del otro
     - Muestra hora (HH:MM)
     - Texto envuelto en Container con BorderRadius

2. **Input de Mensajes (\_ChatInput):**
   - TextField para contenido
   - Botón "Enviar"
   - Al enviar:
     - Dispara `SendMessageEvent(texto)`
     - Limpia TextField
     - No envía si está vacío

**Nota:** El auto-scroll al final se podría mejora con ScrollController

---

## Flujo de Conexiones

### 1. Flujo de Autenticación Completo

```
Usuario abre app
  ↓
main.dart (MultiRepositoryProvider inyecta repos)
  ↓
LoginScreen (login_bloc.dart observa estado)
  ↓
Usuario ingresa email/password → LoginButtonPressed event
  ↓
LoginBloc recibe event → emit(LoginLoading)
  ↓
AuthRepository.login() → POST /auth/login
  ↓
Backend valida credenciales
  ├─ Si OK: responde con JWT
  │   AuthRepository guarda JWT en FlutterSecureStorage
  │   LoginBloc → emit(LoginSuccess)
  │   Screen navega a MatchScreen (borra historial)
  │
  └─ Si FAIL: responde con error
      LoginBloc → emit(LoginFailure)
      Screen muestra SnackBar rojo
```

### 2. Flujo de Registro con OTP

```
RegisterScreen
  ↓
Usuario completa formulario
  ↓
_submitRegister()
  ├─ [Opcional] _scanIdentity() → image_picker → /verification/verify → auto-rellena RUN
  ├─ AuthRepository.register() → POST /auth/register
  │
Backend procesa:
  ├─ Valida email único
  ├─ Crea usuario en DB
  ├─ Genera código OTP (6 dígitos)
  ├─ Envía código vía RabbitMQ → Email
  └─ Responde 200 OK
  ↓
Frontend navega a OTPScreen (email en parámetro)
  ↓
Usuario ingresa código → _verify()
  ↓
AuthRepository.verifyOtp() → POST /auth/otp/verify
  ↓
Backend valida código
  ├─ Si OK: marca usuario como verified → 200
  │   OTPScreen navega a MatchScreen (entrada a app)
  │
  └─ Si FAIL: responde error
      OTPScreen muestra "Código incorrecto"
      Usuario reintenta
```

### 3. Flujo de Matching (Swipes)

```
MatchScreen cargado
  ↓
PetsBloc.add(LoadSwipeDeck)
  ↓
PetsRepository.getSwipeDeck() → GET /matches/candidates
  ├─ Headers: Authorization: Bearer [JWT]
  │
Backend retorna array de mascotas:
  [
    {"id": 1, "name": "Rufus", ...},
    {"id": 2, "name": "Luna", ...},
    ...
  ]
  ↓
PetsBloc → emit(PetsLoaded(pets))
  ↓
MatchView usa FlutterCardSwiper (visualiza cards)
  ↓
Usuario swipea (left/right)
  ↓
flutter_card_swiper dispara onSwipe callback
  ↓
Screen dispara PetsBloc.add(SwipePetEvent(petId, isLike))
  ↓
PetsRepository.swipePet() → POST /matches/swipe (FIRE AND FORGET)
  ├─ No espera respuesta
  │
Backend:
  ├─ Registra swipe en DB
  ├─ Si es Like + la otra mascota también liked: crea Match
  └─ Envía notificación al otro usuario
  ↓
UI ya actualizó (siguiente carta mostrada)
```

### 4. Flujo de Chat en Tiempo Real

```
Usuario toca mascota likeada (from Match List)
  ↓
Navega a ChatScreen(matchId=5, peerName="John")
  ↓
ChatScreen.build() crea BLoC
  ↓
ChatBloc.add(InitChat(5))
  ↓
ChatBloc:
  ├─ PetsRepository.getHistory(5) → GET /matches/5/messages
  │   Carga ultimos N mensajes
  │   emit(ChatLoaded(messages, matchId))
  │
  ├─ PetsRepository.connectToChat() → WS /ws
  │   Handshake con Authorization header
  │   Abre stream escucha
  │
  └─ stream.listen() en background
      Espera mensajes nuevos
      Si llega data → ChatBloc.add(_ReceiveMessageEvent)
      → emit(ChatLoaded) actualizado
  ↓
ChatScreen muestra lista de mensajes + input
  ↓
Usuario tipea "Hola" → _ChatInput.send()
  ↓
ChatBloc.add(SendMessageEvent("Hola"))
  ↓
ChatBloc:
  ├─ Crea ChatMessage local (optimista)
  ├─ emit(ChatLoaded) con nuevo mensaje
  │
  └─ Repository.sendMessage(matchId, "Hola")
      Envía JSON por WebSocket:
      {"match_id": 5, "content": "Hola"}
  ↓
Backend recibe por WS
  ├─ Crea registro en DB
  ├─ Broadcast a otro usuario conectado
  └─ El stream.listen() recibe el mensaje
      → ChatBloc.add(_ReceiveMessageEvent)
      → emit(ChatLoaded) con mensaje del otro
  ↓
UI muestra en burbuja gris (del otro)
```

---

## Flujos de Usuario

### Flujo 1: Nuevo Usuario - Registro Completo

```
1. App inicia → LoginScreen
2. Usuario presiona "¿No tienes cuenta?"
3. Navega a RegisterScreen
4. Completa:
   - Nombre
   - Email
   - Contraseña
   - RUN (manualmente o escaneando identidad)
5. Presiona "Registrar"
6. Backend recibe, envía OTP por email
7. Frontend navega a OTPScreen
8. Usuario copia código del email (6 dígitos)
9. Pega en OTPScreen
10. Presiona "Verificar"
11. Backend valida código
12. Navega a MatchScreen (¡Dentro de la app!)
13. MatchScreen carga mascotas cercanas
```

### Flujo 2: Usuario Existente - Login

```
1. App inicia → LoginScreen
2. Ingresa email y contraseña
3. Presiona "Iniciar Sesión"
4. Backend valida credenciales
5. Responde con JWT
6. Frontend almacena JWT en Keystore/Keychain
7. Navega a MatchScreen
8. Mascotas se cargan automáticamente
```

### Flujo 3: Haciendo Swipes

```
1. En MatchScreen, usuario ve primera mascota (Rufus)
2. Swipea a la DERECHA (Like)
   - Envía: {"pet_id": 1, "is_like": true}
   - Backend registra el like
3. Siguiente mascota (Luna)
4. Swipea a la IZQUIERDA (Dislike)
   - Envía: {"pet_id": 2, "is_like": false}
   - Backend ignora (no crea match)
5. ... continúa con todas las mascotas del mazo
6. Si se agota:
   - Muestra "No hay mascotas nuevas"
   - User vuelve a reintentar después
```

### Flujo 4: Chatear con Match

```
1. Usuario swipeó a "Fluffy" (gato) hace 2 horas
2. Criador de Fluffy también hizo like del usuario
3. Se crea Match automático
4. Notificación: "¡Nuevo Match!"
5. Usuario toca match → ChatScreen(matchId=7, peerName="Sarah")
6. Carga historial (vacío si es primer mensaje)
7. Usuario escribe: "Hola, me encanta tu gato"
8. Backend recibe, guarda en DB
9. Sarah (conectada en mismo match) recibe mensaje en tiempo real
10. Sarah responde: "Gracias, es muy cariñoso"
11. Ambos ven conversación en tiempo real
```

---

## Detalles Técnicos de Implementación

### 1. Manejo de Errores

#### HTTP Errors (via Dio)

```dart
try {
  await _dio.get(url);
} on DioException catch (e) {
  if (e.response != null) {
    // Error del servidor (4xx, 5xx)
    // e.response!.data contiene cuerpo de error
    if (e.response!.data is Map) {
      throw Exception(e.response!.data['error']);
    } else if (e.response!.data is String) {
      // Texto plano (panic del backend)
      throw Exception(e.response!.data);
    }
  } else {
    // Error de red (sin respuesta)
    throw Exception('Error de conexión');
  }
}
```

#### WebSocket Errors

```dart
_wsSubscription = stream.listen(
  (data) {
    // Procesa mensaje
  },
  onError: (error) {
    print("WS Error: $error");
    // Podría reconectar automáticamente
  }
)
```

### 2. Almacenamiento Seguro del JWT

```dart
// Guardando
await FlutterSecureStorage().write(key: 'jwt_token', value: token);

// Leyendo
final token = await FlutterSecureStorage().read(key: 'jwt_token');

// Borrando (logout)
await FlutterSecureStorage().delete(key: 'jwt_token');
```

**Por Qué Seguro:**

- Android: Usa Keystore del sistema
- iOS: Usa Keychain
- No en SharedPreferences (texto plano visible)

### 3. Actualización Optimista

El app usa "Optimistic Updates" para mejor UX:

```dart
// En SwipePetEvent:
// UI actualiza INMEDIATAMENTE
// Request al backend se envía en background
repository.swipePet(...);  // Fire and forget

// En SendMessageEvent:
// Mensaje aparece en chat INMEDIATAMENTE
emit(ChatLoaded(messages: [..., newMsg]));
// Luego se envía al servidor
repository.sendMessage(...);
```

### 4. Decodificación JWT sin Validación

```dart
import 'package:jwt_decoder/jwt_decoder.dart';

Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
int userId = int.tryParse(decodedToken['sub'] ?? decodedToken['user_id'].toString()) ?? 0;
```

**Nota:** Solo decodifica, NO valida firma. Es seguro porque:

- El token vino del servidor confiable
- Solo se usa para obtener user_id localmente
- La validación real ocurre en el servidor

### 5. Inicialización de Widgets

```dart
// En BlocProvider.create(), se instancia BLoC UNA SOLA VEZ
create: (context) => PetsBloc(...)..add(LoadSwipeDeck())
// El ..add() es un cascading operator que llama método en el objeto creado
```

### 6. Navigator - BLoC vs Rutas

**Actual (Imperativo):**

```dart
Navigator.pushAndRemoveUntil(context, MaterialPageRoute(...), (route) => false);
```

**Futuro (Declarativo con GoRouter):**

```dart
// En router/app_router.dart
GoRouter(
  routes: [
    GoRoute(path: '/login', builder: (context, state) => LoginScreen()),
    GoRoute(path: '/match', builder: (context, state) => MatchScreen()),
  ],
)
// En BLoC: context.go('/match')
```

### 7. Cierre de Recursos

**WebSocket:**

```dart
void dispose() {
  _wsSubscription?.cancel();  // Cancela listener
  _channel?.sink.close();      // Cierra conexión
}
```

**TextEditingController:**

```dart
@override
void dispose() {
  _emailController.dispose();
  _passwordController.dispose();
  super.dispose();
}
```

### 8. Límites y Configuración

| Parámetro          | Valor                       | Archivo              |
| ------------------ | --------------------------- | -------------------- |
| Timeout HTTP       | 10 segundos                 | auth_repository.dart |
| Base URL           | http://10.0.2.2:8080/api/v1 | api_constants.dart   |
| OTP Dígitos        | 6                           | otp_screen.dart      |
| Almacenamiento JWT | FlutterSecureStorage        | \*\_repository.dart  |

### 9. Dependencias Internas (Cómo se Conectan)

```
main.dart
  ├─ Inyecta AuthRepository
  ├─ Inyecta PetsRepository
  └─ Inyecta ChatRepository

LoginScreen
  ├─ usa LoginBloc
  │   └─ usa AuthRepository (inyectado)
  └─ navega a RegisterScreen / MatchScreen

RegisterScreen
  ├─ usa _scanIdentity() con ImagePicker
  ├─ usa AuthRepository.register()
  └─ navega a OTPScreen

OTPScreen
  ├─ usa AuthRepository.verifyOtp()
  └─ navega a MatchScreen

MatchScreen
  ├─ usa PetsBloc
  │   └─ usa PetsRepository (inyectado)
  ├─ usa FlutterCardSwiper (UI)
  └─ navega a ChatScreen

ChatScreen
  ├─ usa ChatBloc
  │   └─ usa ChatRepository (inyectado)
  └─ maneja WebSocket stream
```

### 10. Estados No Implementados (TODOs)

- **core/router/**: Migrar de Navigator a GoRouter
- **core/theme/**: Extraer colores, tipografía, estilos a tema centralizado
- **core/errors/**: Crear excepciones personalizadas
- **domain/ (Auth)**: Modelos de entidad (Use Cases)
- **Logout**: Función para borrar JWT y volver a Login
- **Persistencia de datos**: SQLite o Hive para caché local
- **Notificaciones push**: Firebase Cloud Messaging
- **Pruebas unitarias/widgets**: Tests en carpeta test/

---

## Resumen de Archivos

| Archivo              | Líneas | Función                                                |
| -------------------- | ------ | ------------------------------------------------------ |
| main.dart            | ~60    | Punto de entrada, MultiRepositoryProvider, MaterialApp |
| api_constants.dart   | ~15    | URLs y endpoints de API                                |
| auth_repository.dart | 112    | HTTP para Login, Register, OTP                         |
| login_bloc.dart      | 61     | BLoC para estado de Login                              |
| login_screen.dart    | 164    | UI de Login                                            |
| register_screen.dart | 261    | UI de Registro + Image Picker                          |
| otp_screen.dart      | 100+   | UI de Verificación OTP                                 |
| pet_model.dart       | 55     | Modelo de Mascota                                      |
| pets_repository.dart | ~80    | HTTP para mascotas y swipes                            |
| pets_bloc.dart       | ~80    | BLoC para Matching                                     |
| match_screen.dart    | 238    | UI principal con FlutterCardSwiper                     |
| message_model.dart   | ~50    | Modelo de Mensaje                                      |
| chat_repository.dart | ~100   | HTTP + WebSocket para Chat                             |
| chat_bloc.dart       | 149    | BLoC para Chat                                         |
| chat_screen.dart     | 130    | UI de Chat                                             |
| pubspec.yaml         | 110    | Dependencias y configuración                           |

---

## Conclusión

PAWS es una aplicación moderna de Flutter que combina:

✅ **Estado Management**: BLoC para separación clara de lógica  
✅ **Networking**: Dio para HTTP + WebSocket para chat real-time  
✅ **Seguridad**: JWT en FlutterSecureStorage  
✅ **UX Modern**: Animaciones, swipes, chat fluido  
✅ **Escalabilidad**: Clean Architecture para agregar features fácilmente

La arquitectura está bien estructurada para crecer: agregar nuevas features solo requiere:

1. Crear folder en `features/`
2. Implementar data/ (Repository)
3. Implementar domain/ (Models)
4. Implementar presentation/ (BLoC + Screens)
5. Inyectar Repository en main.dart

Próximos pasos recomendados:

- Implementar GoRouter para navegación avanzada
- Agregar temas y estilos centralizados
- Implementar Logout
- Tests unitarios/widgets
- Push Notifications
- Caché local de datos
