# Fase 5: Frontend Flutter con Clean Architecture y BLoC

## Introducción

La Fase 5 representa el salto definitivo de PAWS de una API "sin cara" a una aplicación móvil completa. Se implementa un frontend Flutter que consume la API Go, separando completamente el código frontend del backend. Esta fase introduce una arquitectura móvil de clase empresarial utilizando Clean Architecture combinada con el patrón BLoC (Business Logic Component), permitiendo que múltiples developers trabajen simultáneamente sin conflictos de código.

Adicionalmente, se resuelve uno de los retos más complejos de desarrollo híbrido: hacer que un emulador Android en Windows (simulado en Hyper-V) se comunique con un backend ejecutándose en WSL2 (Linux virtual dentro de Windows) usando un puente de red transparente mediante netsh.

## Objetivos de la Fase 5

1. Desarrollar aplicación Flutter con interfaz moderna y responsiva
2. Implementar Clean Architecture (Domain, Data, Presentation) en el frontend
3. Manejar estado complejo con BLoC pattern
4. Consumir API REST (Dio) desde Flutter
5. Establecer conexiones WebSocket para chat en tiempo real
6. Almacenar tokens JWT de forma segura en el dispositivo
7. Implementar autenticación con login y registro
8. Crear feed de mascotas con interfaz de swipe (Tinder-style)
9. Integrar chat en tiempo real en la aplicación móvil
10. Resolver arquitectura híbrida Windows (emulator) - WSL2 (backend) con netsh portproxy

## Stack Tecnológico Nuevo - Frontend

### Lenguaje y Framework

- **Lenguaje**: Dart 3.10.4
- **Framework Mobile**: Flutter 3.24.0 (aproximado)
- **IDE**: Android Studio / VS Code con Flutter extension

### Dependencias Principales de pubspec.yaml

| Paquete                | Versión | Propósito                                 | Categoría     |
| ---------------------- | ------- | ----------------------------------------- | ------------- |
| flutter                | sdk     | Framework base                            | Core          |
| flutter_bloc           | 9.1.1   | Gestión de estado                         | Architecture  |
| equatable              | 2.0.7   | Comparación de objetos                    | Utilities     |
| dio                    | 5.9.0   | Cliente HTTP (REST)                       | Data          |
| go_router              | 17.0.1  | Navegación moderna                        | Navigation    |
| google_fonts           | 6.3.3   | Tipografías personalizadas                | UI            |
| shared_preferences     | 2.5.4   | Almacenamiento local (plaintext)          | Storage       |
| flutter_secure_storage | 10.0.0  | Almacenamiento seguro (Keystore/Keychain) | Security      |
| flutter_card_swiper    | 7.2.0   | Tarjetas deslizables Tinder-style         | UI            |
| cached_network_image   | 3.4.1   | Cacheo de imágenes de red                 | Performance   |
| web_socket_channel     | 3.0.3   | Cliente WebSocket                         | Communication |
| flutter_lints          | 6.0.0   | Análisis estático de código               | Development   |

### Infraestructura de Desarrollo

- **Sistema Operativo Anfitrión**: Windows 11/10
- **Entorno Backend**: WSL2 (Windows Subsystem for Linux 2)
- **Emulador**: Android Emulator (Hyper-V)
- **Puente de Red**: netsh interface portproxy (Windows Network Stack)
- **Base de Datos**: PostgreSQL 15 (accesible a través del puente)

## Cambios en la Estructura del Proyecto

### Antes (Fase 4): Proyecto Backend Únicamente

```
PAWS-2.0/
├── cmd/
│   └── api/
│       └── main.go
├── internal/
│   ├── core/
│   │   ├── domain/
│   │   └── services/
│   ├── transport/
│   │   ├── http/
│   │   └── websocket/
│   └── platform/
│       └── database/
├── documentation/
├── docker-compose.yml
├── go.mod
├── go.sum
├── .env
└── README.md
```

### Después (Fase 5): Proyecto Monorepo Backend + Frontend

```
PAWS-2.0/                           # Raíz del monorepo
├── app/                            # NUEVO: Frontend Flutter (carpeta separada)
│   ├── lib/
│   │   ├── core/
│   │   │   └── constants/
│   │   │       └── api_constants.dart
│   │   ├── features/                # Clean Architecture: separadas por característica
│   │   │   ├── auth/
│   │   │   │   ├── domain/
│   │   │   │   │   └── (sin archivos - modelos aquí sería overkill para auth)
│   │   │   │   ├── data/
│   │   │   │   │   └── auth_repository.dart
│   │   │   │   └── presentation/
│   │   │   │       ├── bloc/
│   │   │   │       │   └── login_bloc.dart
│   │   │   │       └── screens/
│   │   │   │           ├── login_screen.dart
│   │   │   │           └── register_screen.dart
│   │   │   ├── pets/
│   │   │   │   ├── domain/
│   │   │   │   │   └── pet_model.dart
│   │   │   │   ├── data/
│   │   │   │   │   └── pets_repository.dart
│   │   │   │   └── presentation/
│   │   │   │       ├── bloc/
│   │   │   │       │   └── pets_bloc.dart
│   │   │   │       └── screens/
│   │   │   │           └── feed_screen.dart
│   │   │   └── chat/
│   │   │       ├── domain/
│   │   │       │   └── message_model.dart
│   │   │       ├── data/
│   │   │       │   └── chat_repository.dart
│   │   │       └── presentation/
│   │   │           ├── bloc/
│   │   │           │   └── chat_bloc.dart
│   │   │           └── screens/
│   │   │               └── chat_screen.dart
│   │   └── main.dart
│   ├── android/                    # Configuración Android nativa
│   ├── ios/                        # Configuración iOS nativa (no usado en desarrollo)
│   ├── web/                        # Configuración Web (futuro)
│   ├── test/
│   ├── pubspec.yaml                # Dependencias Flutter
│   ├── pubspec.lock
│   ├── conectar_backend.ps1        # NUEVO: Script PowerShell para netsh
│   ├── paws_app.iml
│   ├── analysis_options.yaml
│   ├── .flutter-plugins-dependencies
│   ├── .metadata
│   └── README.md
├── cmd/
│   └── api/
│       └── main.go                 # (Sin cambios mayores desde Fase 4)
├── internal/
│   ├── core/
│   │   ├── domain/
│   │   └── services/
│   ├── transport/
│   │   ├── http/
│   │   └── websocket/
│   └── platform/
│       └── database/
├── documentation/
├── docker-compose.yml
├── go.mod
├── go.sum
├── .env
├── README.md                       # (ACTUALIZADO para Fase 5)
└── .gitignore
```

**Cambios Clave**:

- Nueva carpeta `app/` alojando el proyecto Flutter completo
- Backend (`cmd/`, `internal/`) permanece en la raíz para facilitar deployment
- Script PowerShell `conectar_backend.ps1` en `app/` para resolver arquitectura híbrida

## Detalles Técnicos Implementados

### 1. Clean Architecture en Flutter

Clean Architecture separa el código en tres capas:

#### Capa Domain (Modelos puros - Lógica de Negocio)

```dart
// Ejemplo: Pet
class Pet {
  final int id;
  final String name;
  final String type;
  final String breed;
  final int age;
  final String description;
  final String status;
  final String imageUrl;

  // Constructor, factory fromJson()
}

// Ejemplo: ChatMessage
class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime timestamp;
}
```

**Responsabilidad**: Definir estructuras de datos sin depender de:

- HTTP (sin Dio)
- Almacenamiento (sin SharedPreferences)
- UI (sin Flutter Widgets)

**Ventaja**: Los modelos son reutilizables y testeables sin contexto Flutter.

#### Capa Data (Repositorios - Acceso a datos)

```dart
// Ejemplo: AuthRepository
class AuthRepository {
  final Dio _dio = Dio(...);
  final FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<void> login(String email, String password) async {
    final response = await _dio.post('/auth/login', ...);
    final token = response.data['token'];
    await _storage.write(key: 'jwt_token', value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }
}
```

**Responsabilidad**: Abstraer cómo se obtienen los datos (HTTP, base de datos local, etc.)

**Ventaja**: Si cambiamos de Dio a otra librería HTTP, solo modificamos un archivo.

#### Capa Presentation (BLoC - Lógica de estado + UI)

```dart
// Estados (Cómo se ve la UI)
abstract class LoginState {}
class LoginInitial extends LoginState {}
class LoginLoading extends LoginState {}
class LoginSuccess extends LoginState {}
class LoginFailure extends LoginState {
  final String error;
}

// BLoC (Lógica)
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final AuthRepository authRepository;

  LoginBloc({required this.authRepository}) {
    on<LoginButtonPressed>((event, emit) async {
      emit(LoginLoading());
      try {
        await authRepository.login(event.email, event.password);
        emit(LoginSuccess());
      } catch (e) {
        emit(LoginFailure(error: e.toString()));
      }
    });
  }
}

// UI (Pantalla)
class LoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginBloc, LoginState>(
      listener: (context, state) {
        if (state is LoginSuccess) {
          Navigator.pushReplacementNamed(context, '/feed');
        }
      },
      child: TextField(...), // Construir UI
    );
  }
}
```

**Responsabilidad**: Separar lógica de estado (BLoC) de la UI (Widgets)

**Ventaja**: La lógica es independiente de Flutter, testeables sin contexto de Widget.

### 2. Patrón BLoC (Business Logic Component)

BLoC es un patrón que gestiona estado mediante **Eventos** y **Estados**.

#### Flujo BLoC

```
Usuario interactúa con UI
      ↓
Event (ej: LoginButtonPressed)
      ↓
BLoC.on<Event>() recibe el evento
      ↓
BLoC emite State (ej: LoginLoading)
      ↓
UI escucha con BlocBuilder/BlocListener
      ↓
UI se redibuja (rebuild)
```

#### Ejemplo Concreto: Login

```dart
// 1. Usuario toca botón login
onPressed: () {
  context.read<LoginBloc>().add(
    LoginButtonPressed(
      email: "juan@example.com",
      password: "password123"
    )
  );
}

// 2. BLoC recibe el evento
on<LoginButtonPressed>((event, emit) async {
  emit(LoginLoading());  // UI muestra spinner
  try {
    await authRepository.login(event.email, event.password);
    emit(LoginSuccess());  // UI navega al feed
  } catch (e) {
    emit(LoginFailure(error: e.toString()));  // UI muestra snackbar rojo
  }
});

// 3. UI escucha cambios
BlocListener<LoginBloc, LoginState>(
  listener: (context, state) {
    if (state is LoginSuccess) {
      Navigator.pushReplacement(...);  // Navegar
    }
    if (state is LoginFailure) {
      ScaffoldMessenger.of(context).showSnackBar(...);  // Mostrar error
    }
  },
  child: LoginForm()
);
```

**Ventajas**:

- Lógica desacoplada de la UI
- Testeabilidad: Puedes testear BLoC sin Widgets
- Reactividad: Cambios automáticos en UI
- State Management predictable

### 3. Consumo de API REST con Dio

```dart
class PetsRepository {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: Duration(seconds: 10),
    receiveTimeout: Duration(seconds: 10),
  ));

  Future<List<Pet>> getPets() async {
    try {
      final response = await _dio.get('${ApiConstants.baseUrl}/pets');

      if (response.statusCode == 200) {
        List<dynamic> data = response.data;
        return data.map((json) => Pet.fromJson(json)).toList();
      }
    } on DioException catch (e) {
      throw Exception('Error: ${e.message}');
    }
  }
}
```

**Características de Dio**:

- Interceptores para headers globales (Authorization)
- Timeouts configurables
- Reintentos automáticos
- Cancelación de requests

### 4. Almacenamiento Seguro de Tokens

#### Inseguro (No Usar):

```dart
SharedPreferences prefs = await SharedPreferences.getInstance();
prefs.setString('token', token);  // Token guardado en plaintext
```

Problema: Cualquiera que tenga acceso al dispositivo jailbroken puede extraer el token.

#### Seguro (Implementado):

```dart
const FlutterSecureStorage storage = FlutterSecureStorage();
await storage.write(key: 'jwt_token', value: token);
```

**En Android**: Token se guarda en AndroidKeyStore (encriptado por el hardware si disponible)
**En iOS**: Token se guarda en Keychain (encriptado por el Secure Enclave)

### 5. Interfaz Swipe (Tinder-style)

```dart
CardSwiper(
  cardsCount: state.pets.length,
  numberOfCardsDisplayed: 3,  // Mostrar pila de 3 tarjetas
  onSwipe: (previousIndex, currentIndex, direction) {
    if (direction == CardSwiperDirection.right) {
      print("Me gusta ${state.pets[currentIndex].name}");
    } else {
      print("No me gusta");
    }
  },
  cardsBuilder: (context, index) {
    final pet = state.pets[index];
    return Card(
      child: Column(
        children: [
          CachedNetworkImage(imageUrl: pet.imageUrl),
          Text(pet.name),
          Text("${pet.breed}, ${pet.age} meses"),
        ],
      ),
    );
  },
)
```

**Características**:

- Swipe hacia la derecha: "Me gusta"
- Swipe hacia la izquierda: "No me gusta"
- Animación suave
- Pila de tarjetas (peek effect)

### 6. Conexión WebSocket para Chat

```dart
class ChatRepository {
  WebSocketChannel? _channel;
  final FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<Stream<dynamic>> connect() async {
    final token = await _storage.read(key: 'jwt_token');
    final uri = Uri.parse('${ApiConstants.wsUrl}?token=$token');

    _channel = WebSocketChannel.connect(uri);
    return _channel!.stream;
  }

  void sendMessage(String message) {
    _channel?.sink.add(message);
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
```

**Protocolo**:

1. Obtener token JWT del almacenamiento seguro
2. Conectar al endpoint WebSocket: `ws://IP:8080/api/v1/chat/ws?token=JWT`
3. Go valida el token y abre la conexión
4. Enviar mensajes: `sink.add(mensaje)`
5. Recibir mensajes: Stream escucha en BLoC

### 7. Inyección de Dependencias en main.dart

```dart
void main() {
  runApp(const PawsApp());
}

class PawsApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (context) => AuthRepository()),
        RepositoryProvider(create: (context) => PetsRepository()),
      ],
      child: MaterialApp(
        home: const LoginScreen(),
      ),
    );
  }
}
```

**Ventaja**: Los repositorios se crean una sola vez en main.dart y están disponibles en toda la app mediante `context.read<AuthRepository>()`.

### 8. Arquitectura Híbrida: Windows + WSL2 + Android Emulator

#### Problema Original:

```
Windows (Emulator) ──┐
                     ├──X→ WSL2 (Backend)
Linux (Host nativo)  ←─ No hay conexión directa
```

El emulador Android no puede alcanzar `localhost:8080` porque:

- localhost en el emulador se refiere al emulador mismo
- WSL2 está en una interfaz de red virtual separada
- Windows actúa como intermediario

#### Solución: netsh interface portproxy

```powershell
# 1. Obtener IP de WSL
$wsl_ip = (wsl hostname -I).Trim().Split(" ")[0]

# 2. Crear puente: 0.0.0.0:8080 (Windows) → WSL_IP:8080
netsh interface portproxy add v4tov4 `
  listenport=8080 `
  listenaddress=0.0.0.0 `
  connectport=8080 `
  connectaddress=$wsl_ip

# 3. Abrir firewall
netsh advfirewall firewall add rule name="WSL Bridge 8080" `
  dir=in action=allow protocol=TCP localport=8080
```

**Resultado**:

```
Emulator (10.0.2.2)
      ↓ (conexión a puerto 8080)
Windows Host (0.0.0.0:8080)
      ↓ (portproxy forwarding)
WSL2 Linux (WSL_IP:8080)
      ↓
Backend Go
```

#### Configuración en Flutter:

```dart
class ApiConstants {
  static const String baseUrl = 'http://192.168.0.4:8080/api/v1';
  static const String wsUrl = 'ws://192.168.0.4:8080/api/v1/chat/ws';
}
```

**192.168.0.4** es la IP del host Windows en la red local (accesible desde el emulador).

El script `conectar_backend.ps1` automatiza todo esto.

### 9. Flujos de Comunicación Completos

#### Flujo 1: Autenticación (Login)

```
1. Usuario entra email y password en LoginScreen
2. Toca "Iniciar Sesión"
3. LoginScreen dispara: context.read<LoginBloc>().add(LoginButtonPressed(...))
4. LoginBloc recibe evento
   - Emite LoginLoading() → UI muestra spinner
   - Llama authRepository.login()
5. AuthRepository hace POST a Go backend
   - POST /api/v1/auth/login
   - Go valida credenciales contra PostgreSQL
   - Go responde con JWT
6. AuthRepository guarda JWT en FlutterSecureStorage (Keystore)
7. LoginBloc emite LoginSuccess()
8. LoginScreen escucha LoginSuccess
9. Navega a FeedScreen
10. FeedScreen cargar mascotas
```

#### Flujo 2: Feed de Mascotas (Swipe)

```
1. Usuario ve FeedScreen
2. FeedScreen crea PetsBloc y dispara LoadPets()
3. PetsBloc emite PetsLoading()
4. FeedScreen muestra spinner
5. PetsRepository hace GET /api/v1/pets
6. Go backend retorna lista de mascotas en JSON
7. Flutter mapea JSON a objetos Pet
8. PetsBloc emite PetsLoaded(pets)
9. FeedScreen muestra CardSwiper con 3 tarjetas
10. Usuario swipe derecha: "Me gusta Max"
11. App registra swipe (sin guardar a BD por ahora, es solo demo)
12. Siguiente tarjeta se muestra
```

#### Flujo 3: Chat en Tiempo Real

```
1. Usuario toca ícono chat en AppBar
2. FeedScreen navega a ChatScreen
3. ChatScreen crea ChatBloc y dispara ConnectChat()
4. ChatBloc obtiene token de FlutterSecureStorage
5. ChatRepository abre WebSocket: ws://...?token=JWT
6. Go backend recibe conexión, valida JWT
7. ChatRepository retorna Stream al BLoC
8. ChatBloc emite ChatActive([])
9. ChatScreen muestra pantalla de chat vacía
10. Usuario escribe "Hola" y toca send
11. ChatScreen dispara SendMessage("Hola")
12. ChatBloc llama repository.sendMessage()
13. ChatRepository envía por WebSocket: sink.add("Hola")
14. Go backend recibe, filtra (¿malas palabras?), distribuye por Redis
15. Todos los clientes reciben el mensaje
16. ChatBloc recibe mensaje del stream
17. ChatBloc emite ChatActive([...messages, newMessage])
18. ChatScreen se redibuja con el nuevo mensaje
```

### 10. Gestión de Errores y Reintentos

```dart
// Ejemplo: PetsBloc con manejo de errores
on<LoadPets>((event, emit) async {
  emit(PetsLoading());
  try {
    final pets = await repository.getPets();
    emit(PetsLoaded(pets));
  } catch (e) {
    emit(PetsError(e.toString()));  // Mostrar error
  }
});

// En UI:
if (state is PetsError) {
  return Column(
    children: [
      Text("Error: ${state.message}"),
      ElevatedButton(
        onPressed: () => context.read<PetsBloc>().add(LoadPets()),
        child: const Text("Reintentar"),
      ),
    ],
  );
}
```

## Cambios Detectados desde Fase 4

| Cambio                      | Tipo          | Impacto                               | Categoría        |
| --------------------------- | ------------- | ------------------------------------- | ---------------- |
| **Nueva carpeta app/**      | Estructura    | Proyecto Flutter completo             | Arquitectura     |
| **pubspec.yaml**            | Dependencias  | flutter_bloc, dio, web_socket_channel | Framework        |
| **Clean Architecture**      | Patrón        | Domain/Data/Presentation separadas    | Arquitectura     |
| **BLoC para estado**        | Patrón        | Reemplazo de setState/Provider        | State Management |
| **ApiConstants**            | Configuración | Endpoint configurable (192.168.0.4)   | Networking       |
| **AuthRepository**          | Data layer    | Gestión de login/registro y tokens    | Authentication   |
| **PetsRepository**          | Data layer    | Consumo GET /api/v1/pets              | Data Access      |
| **ChatRepository**          | Data layer    | WebSocket con token JWT               | Real-time        |
| **LoginBloc/Screen**        | Feature       | Autenticación con validación          | Feature          |
| **PetsBloc/FeedScreen**     | Feature       | Feed swipeable Tinder-style           | Feature          |
| **ChatBloc/ChatScreen**     | Feature       | Chat en tiempo real distribuido       | Feature          |
| **conectar_backend.ps1**    | DevOps        | Script netsh para puente red          | Infrastructure   |
| **FlutterSecureStorage**    | Security      | Almacenamiento seguro de JWT          | Security         |
| **Dio con BaseOptions**     | Networking    | Timeouts, retry logic                 | Networking       |
| **CardSwiper**              | UI Component  | Interfaz swipe para mascotas          | UI               |
| **CachedNetworkImage**      | Performance   | Cacheo de imágenes                    | Performance      |
| **MultiRepositoryProvider** | DI            | Inyección de dependencias global      | Architecture     |

## Decisiones Arquitectónicas Importantes

### 1. Clean Architecture vs MVC

**Elegido**: Clean Architecture
**Razón**: Escalabilidad y testeabilidad

Clean Architecture permite:

- Domain: Lógica sin dependencias externas
- Data: Múltiples implementaciones (mock en tests, real en prod)
- Presentation: UI desacoplada de lógica

MVC sería más simple pero menos flexible para crecimiento.

### 2. BLoC vs Riverpod vs Provider

**Elegido**: BLoC
**Razón**: Comunidad más grande en Flutter

BLoC es:

- Más verboso pero explícito
- Mejor para equipos grandes (patrón claro)
- Amplia documentación oficial Flutter

Riverpod sería más simple pero BLoC es más educativo.

### 3. Dio vs http vs chopper

**Elegido**: Dio
**Razón**: Mejor soporte para interceptores y reintentos

```dart
// Interceptor para agregar Authorization header
_dio.interceptors.add(
  InterceptorsWrapper(
    onRequest: (options, handler) {
      // Agregar token a todos los requests
      return handler.next(options);
    },
  ),
);
```

### 4. Almacenamiento de Token: FlutterSecureStorage vs Dart:io

**Elegido**: FlutterSecureStorage
**Razón**: Hardware-backed encryption

```dart
// Seguro (implementado)
FlutterSecureStorage().write(key: 'jwt_token', value: token);

// Inseguro (evitar)
File('token.txt').writeAsString(token);
SharedPreferences.setString('token', token);
```

### 5. WebSocket: web_socket_channel vs socket_io_client

**Elegido**: web_socket_channel
**Razón**: Compatible con protocolo estándar WebSocket

Go usa gorilla/websocket (protocolo estándar).
web_socket_channel implementa RFC 6455 (WebSocket Protocol).

### 6. Red Híbrida: netsh vs SSH Tunnel vs nginx

**Elegido**: netsh portproxy
**Razón**: Sin dependencias, built-in en Windows

```powershell
# Transparente
netsh interface portproxy add v4tov4 listenport=8080 connectaddress=WSL_IP

# vs Alternativa: SSH Tunnel (requiere servidor SSH)
ssh -L 8080:localhost:8080 user@wsl-ip
```

## Stack Completo Fase 5

### Frontend

| Capa             | Tecnología             | Versión         |
| ---------------- | ---------------------- | --------------- |
| UI Framework     | Flutter                | 3.24.0 (approx) |
| Language         | Dart                   | 3.10.4          |
| State Management | flutter_bloc           | 9.1.1           |
| HTTP Client      | Dio                    | 5.9.0           |
| WebSocket        | web_socket_channel     | 3.0.3           |
| Secure Storage   | flutter_secure_storage | 10.0.0          |
| Navigation       | go_router              | 17.0.1          |
| Cache Network    | cached_network_image   | 3.4.1           |
| Cards Swiper     | flutter_card_swiper    | 7.2.0           |
| Testing          | flutter_test           | sdk             |

### Backend (Sin cambios desde Fase 4)

| Componente     | Tecnología | Versión |
| -------------- | ---------- | ------- |
| Language       | Go         | 1.24.0  |
| Web Framework  | Gin        | 1.11.0  |
| Database       | PostgreSQL | 15      |
| ORM            | GORM       | 1.31.1  |
| WebSocket      | Gorilla    | 1.5.3   |
| Pub/Sub        | Redis      | Latest  |
| Authentication | JWT v5     | 5.3.0   |

## Estructura de Features: Domain, Data, Presentation

Cada feature (Auth, Pets, Chat) sigue la misma estructura:

```
feature/
├── domain/
│   └── model.dart              # Entidades puras (sin dependencias)
├── data/
│   └── repository.dart          # Acceso a datos (Dio, WebSocket, etc)
└── presentation/
    ├── bloc/
    │   └── feature_bloc.dart   # Lógica de estado
    └── screens/
        └── feature_screen.dart  # UI
```

**Ventajas**:

1. **Cohesión**: Toda lógica relacionada a una feature en una carpeta
2. **Modularidad**: Agregar nueva feature es copiar la estructura
3. **Testeabilidad**: Cada capa se testea independientemente
4. **Escalabilidad**: Equipo A trabaja en Auth, Equipo B en Pets, sin conflictos

## Próximos Pasos (Fase 6)

### Funcionalidades de App

1. **Perfil de Usuario**: Editar nombre, foto, descripción
2. **Favorites**: Guardar mascotas favoritas (REALM o SQLite local)
3. **Notificaciones Push**: Firebase Cloud Messaging
4. **Ubicación Real**: google_maps_flutter + geolocalización
5. **Galería**: Cargar fotos del dispositivo
6. **Videollamada**: Agora.io o Twilio

### Infraestructura

1. **Testing Automatizado**: Unit tests para BLoCs, Widget tests para UI
2. **CI/CD**: GitHub Actions para build automático
3. **Crashlytics**: Firebase Crashlytics para logging de errores
4. **Analytics**: Firebase Analytics para tracking de eventos
5. **Despliegue**: Deploy a Google Play Store y Apple App Store

## Referencias y Recursos

- **Flutter Bloc Pattern**: https://bloclibrary.dev/
- **Clean Architecture**: https://resocoder.com/flutter-clean-architecture-tdd
- **Dio HTTP Client**: https://pub.dev/packages/dio
- **WebSocket RFC 6455**: https://tools.ietf.org/html/rfc6455
- **WSL2 Networking**: https://docs.microsoft.com/en-us/windows/wsl/networking
- **Android Emulator Networking**: https://developer.android.com/studio/run/emulator-networking
- **Secure Storage Best Practices**: https://owasp.org/www-community/Sensitive_Data_Exposure
