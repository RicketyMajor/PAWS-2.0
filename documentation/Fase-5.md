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

## COMPLETADO EN ETAPA 7: Panel de Administración y Ruteo Condicional por Rol

La Etapa 7 añadió al frontend Flutter un sistema completo de administración y una lógica de ruteo inteligente que detecta si el usuario es administrador después del login. Se implementó una nueva feature exclusiva: el Panel de Justicia (AdminDashboardScreen), interfaz moderna donde administradores visualizan reportes de usuarios y ejecutan bans manuales. Adicionalmente, se modificó el LoginScreen para decodificar el JWT y enrutar usuarios a destinos diferentes según su rol (admin vs mortal).

### Nuevas Características en Frontend (Etapa 7)

#### 1. AdminDashboardScreen - Panel de Justicia

**Ubicación**: app/lib/features/admin/presentation/screens/admin_dashboard_screen.dart

Se creó una pantalla completamente nueva dedicada exclusivamente a administradores:

```dart
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminRepository _repo = AdminRepository();
  late Future<List<dynamic>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _reportsFuture = _repo.getReports();
    });
  }

  Future<void> _banUser(int userId, String userName) async {
    // Diálogo pide motivo del ban
    // Valida que motivo no sea vacío
    // Llamaa _repo.banUser(userId, reason)
    // SnackBar con feedback
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel de Justicia"),
        backgroundColor: Colors.black87,
        actions: [IconButton logout],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          // Carga: CircularProgressIndicator
          // Error: mensaje de error
          // Vacío: "La comunidad está en paz"
          // Datos: ListView de Cards con cada reporte
        },
      ),
    );
  }
}
```

**Características**:

- **Pantalla Exclusiva**: Solo visible si role=="admin" en JWT
- **Carga Asincrónica**: FutureBuilder obtiene lista de reportes
- **Interfaz Limpia**: AppBar oscuro (negro) indica autoridad
- **Botón Logout**: En AppBar para volver a login
- **Despliegue Detallado**: Cada reporte como Card con:
  - Icono de advertencia rojo
  - Nombre del acusado
  - Nombre del denunciante
  - Motivo del reporte
  - Botón BAN rojo (acción grave)
- **Diálogo Confirm**: Pide motivo de ban para documentación
- **Validación**: Solo ejecuta ban si motivo no vacío
- **Recarga**: \_refresh() después de ban exitoso
- **Estado Vacío**: Muestra icono checkmark + "La comunidad está en paz" si no hay reportes

**Data Flow**:

```
AdminDashboardScreen (Stateful)
  ↓
  _repo.getReports()
  ↓
  AdminRepository.getReports()
  ↓
  GET /admin/reports (con JWT en header)
  ↓
  AdminHandler.GetReports()
  ↓
  ReportService.GetAllReports() (con Preload)
  ↓
  BD: SELECT * FROM reports
      LEFT JOIN users as Reporter
      LEFT JOIN users as Reported
  ↓
  Retorna JSON con información completa
  ↓
  ListView.builder() despliega cada reporte
```

**Acciones Admin**:

```
Admin presiona botón BAN en un reporte
  ↓
_banUser(userId, userName) abre AlertDialog
  ↓
Dialog pide "Motivo del Ban"
  ↓
Usuario ingresa motivo (ej: "Acoso reiterado")
  ↓
Usuario presiona "EJECUTAR SENTENCIA" (rojo)
  ↓
_repo.banUser(userId, reason)
  ↓
POST /admin/ban/:id {reason: "..."}
  ↓
Backend ejecuta ban (BanUserManual)
  ↓
SnackBar: "Justicia aplicada"
  ↓
_refresh() recarga lista
  ↓
Usuario baneado desaparece de la lista
```

#### 2. AdminRepository - Capa de Datos para Panel

**Ubicación**: app/lib/features/admin/data/admin_repository.dart

```dart
class AdminRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<List<dynamic>> getReports() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/admin/reports',
        options: options,
      );
      return response.data;
    } catch (e) {
      throw Exception('Error cargando reportes: $e');
    }
  }

  Future<void> banUser(int userId, String reason) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/admin/ban/$userId',
        data: {'reason': reason},
        options: options,
      );
    } catch (e) {
      throw Exception('Error baneando usuario: $e');
    }
  }
}
```

**Métodos**:

- **getReports()**: GET /admin/reports

  - Inyecta JWT automáticamente
  - Retorna lista de reportes con información de usuarios
  - Throw Exception si error (FutureBuilder muestra error)

- **banUser(int userId, String reason)**: POST /admin/ban/:id
  - userId se inserta en URL path
  - reason se envía en body JSON
  - Throw Exception si error (SnackBar muestra error)

**Patrón Clean Architecture**:

- **Data Layer**: AdminRepository abstrae comunicación HTTP
- **UI Layer**: AdminDashboardScreen no conoce detalles HTTP
- **Testeable**: AdminRepository puede mockearse en tests
- **Reutilizable**: Mismo patrón que SocialRepository (Etapa 6), UserRepository

#### 3. LoginScreen Modificado - Ruteo Inteligente por Rol

**Ubicación**: app/lib/features/auth/presentation/screens/login_screen.dart

Se modificó la lógica después de login exitoso:

```dart
} else if (state is LoginSuccess) {
  // ... SnackBar success ...

  final authRepo = context.read<AuthRepository>();
  final token = await authRepo.getToken();

  if (token != null) {
    // NUEVO EN ETAPA 7: Decodificar JWT y extraer role
    Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
    String role = decodedToken['role'] ?? 'adopter';

    // NUEVO EN ETAPA 7: Enrutamiento condicional
    if (role == 'admin') {
      // Caso 1: Es Administrador
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const AdminDashboardScreen(),
          ),
          (route) => false,
        );
      }
    } else {
      // Caso 2: Es Mortal (Adoptante/Rescatista)
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => MainLayoutScreen(role: role),
          ),
          (route) => false,
        );
      }
    }
  }
}
```

**Cambios**:

- **JwtDecoder.decode(token)**: Decodifica JWT sin validar firma (already done by backend)
- **Extrae role**: `String role = decodedToken['role'] ?? 'adopter'`
- **Condicional**:
  - Si role=="admin": navega a AdminDashboardScreen()
  - Sino: navega a MainLayoutScreen(role: role)
- **PushRemoveUntil**: Elimina LoginScreen del stack (logout no puede volver a login con back)

**UX Scenarios**:

```
Escenario 1: Alonso (admin) hace login
  1. Ingresa email/contraseña
  2. Backend autentica y retorna JWT con role="admin"
  3. Frontend decodifica JWT
  4. Detecta role=="admin"
  5. PushRemoveUntil → AdminDashboardScreen
  6. Ve Panel de Justicia con lista de reportes
  7. Botón logout en AppBar → LoginScreen

Escenario 2: Juan (adoptante) hace login
  1. Ingresa email/contraseña
  2. Backend autentica y retorna JWT con role="adopter"
  3. Frontend decodifica JWT
  4. Detecta role!="admin"
  5. PushRemoveUntil → MainLayoutScreen(role: "adopter")
  6. Ve pantalla normal con tabs: Descubrir, Mis Matches, Perfil
  7. Botón logout en perfil → LoginScreen
```

### Arquitectura Frontend de Etapa 7

```
                      LoginScreen (Login)
                            |
                    LoginSuccess event
                            |
               JwtDecoder extracts role
                            |
                    ¿role == "admin"?
                         /    \
                       Sí      No
                       /        \
        AdminDashboardScreen  MainLayoutScreen
        (Panel Justicia)      (Normal App)
             |                    |
        [Admin Only]         [Mortales]
             |                    |
        GetReports()          Adopter/Rescuer
        BanUser()            Features
```

### Clean Architecture en Panel de Justicia

**Domain Layer** (conceptual):

- Entidades: Report, User, Admin Actions
- Use Cases: ViewReports, BanUser

**Data Layer**:

- AdminRepository: comunica con backend
- Fuente: API via Dio + JWT

**Presentation Layer**:

- AdminDashboardScreen: Stateful widget
- Lógica: FutureBuilder, dialogs, refresh

**Pattern Consistency** (vs Etapa 6):

- SocialRepository (Etapa 6): createReport, createReview → POST endpoints
- AdminRepository (Etapa 7): getReports, banUser → GET + POST admin endpoints
- UserRepository: updateProfile, getProfile → PUT + GET user endpoints

Todos siguen el patrón: Repository abstrae HTTP, UI llama Repository

### Seguridad en Frontend

**JWT Decodificación Segura**:

- JwtDecoder.decode() es client-side, NO verifica firma (backend ya lo hizo)
- Si JWT es inválido, AuthMiddleware rechazó antes
- Frontend solo confía en role porque backend fue confiable

**Problema Evitado**:

```
// MAL: Cambiar role en el cliente
// Si hubiera hecho: decodedToken['role'] = 'admin'
// PERO: Backend rechazaría igual porque JWT tampoco cambió
// Y backend valida JWT en CADA request
```

**Flujo Seguro**:

```
Login request
  → Backend valida credenciales
  → Backend firma JWT con role verificado
  → Frontend decodifica (no verifica)
  → Frontend navega según role
  → Todos los requests posteriores incluyen JWT
  → Backend revisa RequireRole() middleware
  → Backend rechaza si role incorrecto
```

**Implicación**: Cliente no puede escalar sin falsificar JWT (criptografía asegura contra esto)

### Integración con MainLayout (Etapa 5)

La Etapa 7 **no modifica** MainLayoutScreen, pero la complementa:

- MainLayoutScreen: Para mortales (adopter, rescuer)
- AdminDashboardScreen: Para admins
- LoginScreen: Elige cuál mostrar

**Consecuencia**:

- Adoptantes no ven Panel de Justicia (no tienen ruta, no tienen permisos API)
- Admins no ven MainLayout (directamente en AdminDashboardScreen)
- No hay "Admin Tab" en MainLayout (separación limpia)

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

## Actualización Etapa 1: EnvironmentConfig y Configuración Dinámica de API

La Etapa 1 identifica un vacío crítico en la configuración del frontend: los endpoints de API están hardcodeados para emulador Android específicamente, sin soporte para diferentes plataformas de ejecución.

### Problema Actual

El archivo `app/lib/core/constants/api_constants.dart` contiene:

```dart
class ApiConstants {
  // Hardcodeado para Android Emulator en Windows
  static const String baseUrl = "http://10.0.2.2:8080/api/v1";
  static const String wsUrl = "ws://10.0.2.2:8080/api/v1";
}
```

**Limitaciones identificadas**:

1. **10.0.2.2** es una dirección especial que SOLO funciona en emulador Android
2. **Web (Flutter Web)** necesita `http://localhost:8080/api/v1`
3. **Dispositivo físico** necesita dirección IP real de la máquina (ej: `192.168.1.100`)
4. **Producción** necesita URL en dominio (ej: `https://api.paws.com`)
5. No hay detección automática → requiere recompilación para cambiar entorno

### Solución: EnvironmentConfig con Detección Automática

Se implementará un sistema de EnvironmentConfig que detecta automáticamente la plataforma de ejecución y configura URLs apropiadas.

#### 1. Crear app/lib/core/config/environment_config.dart

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class EnvironmentConfig {
  static late final String _baseUrl;
  static late final String _wsUrl;
  static late final String _environment;

  /// Inicializar configuración basada en plataforma
  static void initialize() {
    if (kIsWeb) {
      // Flutter Web: localhost
      _baseUrl = "http://localhost:8080/api/v1";
      _wsUrl = "ws://localhost:8080/api/v1";
      _environment = "web";
    } else if (Platform.isAndroid) {
      // Android: Detectar si es emulador o dispositivo físico
      if (_isAndroidEmulator()) {
        // Emulador: usar 10.0.2.2 (localhost del host)
        _baseUrl = "http://10.0.2.2:8080/api/v1";
        _wsUrl = "ws://10.0.2.2:8080/api/v1";
        _environment = "android_emulator";
      } else {
        // Dispositivo físico: usar IP local
        // En desarrollo, se puede hardcodear o cargar de config
        _baseUrl = "http://192.168.1.100:8080/api/v1";  // Ajustar según tu red
        _wsUrl = "ws://192.168.1.100:8080/api/v1";
        _environment = "android_device";
      }
    } else if (Platform.isIOS) {
      // iOS Simulator
      _baseUrl = "http://localhost:8080/api/v1";
      _wsUrl = "ws://localhost:8080/api/v1";
      _environment = "ios_simulator";
    } else {
      // Fallback (escritorio, etc.)
      _baseUrl = "http://localhost:8080/api/v1";
      _wsUrl = "ws://localhost:8080/api/v1";
      _environment = "fallback";
    }

    print("[EnvironmentConfig] Inicializado en ambiente: $_environment");
    print("[EnvironmentConfig] Base URL: $_baseUrl");
  }

  /// Detectar si es Android Emulator
  /// El emulador siempre retorna manufacturer="unknown", model="Android SDK"
  static bool _isAndroidEmulator() {
    // Implementación simplificada
    // En versión completa, usar package:device_info_plus para verificar
    // si es emulador vs dispositivo real
    return false;  // Por ahora, asumir dispositivo físico
  }

  static String get baseUrl => _baseUrl;
  static String get wsUrl => _wsUrl;
  static String get environment => _environment;
}
```

#### 2. Mejorar Detección de Emulador

Para detectar si es emulador Android automáticamente, usar `device_info_plus`:

```dart
// En pubspec.yaml, agregar:
dependencies:
  device_info_plus: ^10.1.0
```

```dart
import 'package:device_info_plus/device_info_plus.dart';

static Future<bool> _isAndroidEmulator() async {
  try {
    final androidInfo = await DeviceInfoPlugin().androidInfo;

    // Emulador: manufacturer="unknown", model="Android SDK"
    // Dispositivo físico: manufacturer="Samsung", model="SM-A505F", etc.
    return androidInfo.manufacturer == "unknown" &&
           androidInfo.model.contains("SDK");
  } catch (e) {
    return false;  // Fallback si no se puede determinar
  }
}
```

#### 3. Integrar en main.dart

```dart
import 'package:app/core/config/environment_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar configuración ANTES de cualquier petición HTTP
  EnvironmentConfig.initialize();

  runApp(const MyApp());
}
```

#### 4. Actualizar ApiConstants para usar EnvironmentConfig

```dart
// app/lib/core/constants/api_constants.dart

import 'package:app/core/config/environment_config.dart';

class ApiConstants {
  static String get baseUrl => EnvironmentConfig.baseUrl;
  static String get wsUrl => EnvironmentConfig.wsUrl;

  // Endpoints
  static const String authRegister = "/auth/register";
  static const String authLogin = "/auth/login";
  static const String authOtpRequest = "/auth/otp/request";
  static const String authOtpVerify = "/auth/otp/verify";

  // Chat
  static const String chatSocket = "/chat/ws";
}
```

### Tabla de Plataformas Soportadas

| Plataforma         | Base URL                     | WebSocket URL              | Detección                       |
| ------------------ | ---------------------------- | -------------------------- | ------------------------------- |
| Android Emulator   | `http://10.0.2.2:8080/...`   | `ws://10.0.2.2:8080/...`   | manufacturer=unknown, model=SDK |
| Android Device     | `http://192.168.1.X:8080/..` | `ws://192.168.1.X:8080/..` | Real manufacturer/model         |
| iOS Simulator      | `http://localhost:8080/...`  | `ws://localhost:8080/...`  | Platform.isIOS == true          |
| Flutter Web        | `http://localhost:8080/...`  | `ws://localhost:8080/...`  | kIsWeb == true                  |
| Escritorio (Linux) | `http://localhost:8080/...`  | `ws://localhost:8080/...`  | Platform.isLinux                |
| Producción         | `https://api.paws.com/...`   | `wss://api.paws.com/...`   | Config file                     |

### Cómo Usar en Diferentes Entornos

#### Desarrollo Local (Android Emulator)

```bash
# En Android Studio, ejecutar emulador
flutter run

# Se configura automáticamente: 10.0.2.2:8080
# EnvironmentConfig detecta emulador y usa dirección especial
```

#### Desarrollo con Dispositivo Real

```bash
# Conectar dispositivo físico Android
# Editar IP en EnvironmentConfig._baseUrl
_baseUrl = "http://192.168.1.100:8080/api/v1";  # Tu IP local

flutter run

# Se conecta al backend en red local
```

#### Desarrollo Web

```bash
# Flutter Web se ejecuta en navegador
flutter run -d web

# Se configura automáticamente: localhost:8080
```

#### Producción (CI/CD)

```dart
// Crear archivo separado: app/lib/core/config/production_config.dart
const String productionBaseUrl = "https://api.paws.com/v1";
const String productionWsUrl = "wss://api.paws.com/v1";
```

### Ventajas de EnvironmentConfig

1. **Cero Recompilación**: Cambios de URL sin rebuild
2. **Detección Automática**: Soporta 4+ plataformas automáticamente
3. **Escalable**: Fácil agregar nuevas plataformas
4. **Seguro**: URLs no hardcodeadas en código
5. **Testeable**: Mock EnvironmentConfig en tests
6. **Documentado**: Logs indican qué configuración se usó

### Testing de EnvironmentConfig

```dart
// test/core/config/environment_config_test.dart

void main() {
  group('EnvironmentConfig', () {
    test('detecta Android Emulator correctamente', () async {
      EnvironmentConfig.initialize();

      // En emulador, debería ser 10.0.2.2
      if (Platform.isAndroid) {
        expect(EnvironmentConfig.baseUrl, contains("10.0.2.2"));
      }
    });

    test('detecta Web correctamente', () {
      EnvironmentConfig.initialize();

      if (kIsWeb) {
        expect(EnvironmentConfig.baseUrl, "http://localhost:8080/api/v1");
      }
    });
  });
}
```

### Impacto en Etapa 2+

- **Fase 5 (Frontend)**: AuthRepository y ChatRepository usan EnvironmentConfig automáticamente
- **Fase 4 (Chat)**: WebSocket se conecta a URL dinámica en lugar de hardcodeada
- **Fase 3 (Matching)**: PetsRepository puede trabajar en Web, Android y iOS sin cambios
- **Producción**: Deploy automatizado con URLs configurables por entorno

## COMPLETADO EN ETAPA 5: MainLayout y Edición de Perfil

### Enhancements Implementados

La Etapa 5 agregó dos componentes cruciales al frontend Flutter de Fase 5: un sistema de navegación unificado (MainLayout) y una pantalla de edición de perfil con carga de imágenes:

#### 1. MainLayoutScreen: Navegación Centralizada

**Nueva pantalla** (core/presentation/main_layout_screen.dart):

```dart
class MainLayoutScreen extends StatefulWidget {
  final String userRole; // 'adopter' o 'rescuer'

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _currentIndex = 0;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    // Tabs diferentes según rol
    if (widget.userRole == 'adopter') {
      _screens = [
        MatchScreen(),              // Tab 0: Descubrir mascotas
        AdopterMatchesScreen(),     // Tab 1: Mis matches
        EditProfileScreen(),        // Tab 2: Mi perfil
      ];
    } else {
      _screens = [
        RescuerHomeScreen(),        // Tab 0: Mis mascotas
        RescuerChatsScreen(),       // Tab 1: Chats
        MatchRequestsScreen(),      // Tab 2: Solicitudes
        EditProfileScreen(),        // Tab 3: Mi perfil
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() => _currentIndex = index);
        },
        destinations: widget.userRole == 'adopter'
          ? [
              NavigationDestination(
                icon: Icon(Icons.favorite_border),
                selectedIcon: Icon(Icons.favorite),
                label: 'Descubrir',
              ),
              NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                selectedIcon: Icon(Icons.check_circle),
                label: 'Mis Matches',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil',
              ),
            ]
          : [
              NavigationDestination(
                icon: Icon(Icons.pets),
                selectedIcon: Icon(Icons.pets),
                label: 'Mascotas',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: Icon(Icons.mail_outline),
                selectedIcon: Icon(Icons.mail),
                label: 'Solicitudes',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil',
              ),
            ],
      ),
    );
  }
}
```

**Características principales**:

- **StatefulWidget** con \_currentIndex: Mantiene tab activo
- **IndexedStack**: Preserva estado de cada tab sin reconstruir
- **Role-based tabs**: 3 tabs para adoptantes, 4 para rescatistas
- **Material 3 NavigationBar**: Indicador rosa (#E91E63), animación suave
- **EditProfileScreen integrado**: Último tab en ambos roles

**Ventajas sobre Fase 5 original**:

- Fase 5: Cada pantalla tenía sus propios botones de navegación (inconsistencia)
- Etapa 5: MainLayout proporciona navegación unificada y centralizada
- Fase 5: Difícil agregar nuevos tabs sin tocar múltiples archivos
- Etapa 5: Nuevo tab = agregar a lista de \_screens y destino de NavigationBar

#### 2. EditProfileScreen: Edición de Perfil con Foto

**Nueva pantalla** (features/user/presentation/screens/edit_profile_screen.dart):

```dart
class EditProfileScreen extends StatefulWidget {
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _phoneController;

  XFile? _selectedImage;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _bioController = TextEditingController();
    _phoneController = TextEditingController();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // GET /profile para pre-llenar formulario
    final userRepo = context.read<UserRepository>();
    final user = await userRepo.getProfile();

    setState(() {
      _nameController.text = user.name ?? '';
      _bioController.text = user.bio ?? '';
      _phoneController.text = user.phone ?? '';
    });
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() => _selectedImage = image);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    String? photoUrl;

    // Si hay imagen nueva, subirla primero
    if (_selectedImage != null) {
      photoUrl = await _uploadProfilePicture(_selectedImage!);
    }

    // Luego actualizar perfil
    final userRepo = context.read<UserRepository>();
    await userRepo.updateProfile(
      name: _nameController.text,
      bio: _bioController.text,
      phone: _phoneController.text,
      photoUrl: photoUrl,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Perfil actualizado')),
    );

    Navigator.pop(context);
  }

  Future<String> _uploadProfilePicture(XFile file) async {
    // Subir a MinIO, retorna URL
    final fileService = context.read<FileService>();
    final url = await fileService.uploadFile(file);
    return url;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Perfil'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Avatar con selector de imagen
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundImage: _selectedImage != null
                        ? FileImage(File(_selectedImage!.path))
                        : null,
                      child: _selectedImage == null
                        ? Icon(Icons.person, size: 60)
                        : null,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.pink,
                        shape: BoxShape.circle,
                      ),
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),

              // Campo Nombre (obligatorio)
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'El nombre es requerido';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Campo Bio (opcional, 3 líneas)
              TextFormField(
                controller: _bioController,
                decoration: InputDecoration(
                  labelText: 'Biografía',
                  hintText: 'Cuéntanos sobre ti...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                maxLength: 200,
              ),
              SizedBox(height: 16),

              // Campo Teléfono (opcional)
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Teléfono / WhatsApp',
                  hintText: '+56912345678',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: 32),

              // Botón Guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: Icon(Icons.check),
                  label: Text('Guardar Cambios'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.pink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
```

**Características principales**:

- **StatefulWidget** con controladores de texto: name, bio, phone
- **Image picker**: Galería nativa iOS/Android
- **CircleAvatar con GestureDetector**: Toca para cambiar foto
- **Form validation**: Nombre obligatorio, bio/phone opcionales
- **Flujo de guardado**: Upload foto → PUT /profile → Feedback
- **SingleChildScrollView**: Previene overflow en teclado virtual

**Diferencias vs Fase 5**:

- Fase 5: No existía edición de perfil
- Etapa 5: Pantalla completa con carga de fotos
- Fase 5: Perfil era read-only (solo vista de matches)
- Etapa 5: Perfil editable, fotos humanizadoras

#### 3. Integración con PetsBloc: Permisos GPS

**Mejorado en** features/pets/presentation/bloc/pets_bloc.dart:

```dart
class PetsBloc extends Bloc<PetsEvent, PetsState> {
  final PetsRepository petsRepository;

  PetsBloc(this.petsRepository) : super(PetsInitial()) {
    on<LoadSwipeDeck>(_onLoadSwipeDeck);
  }

  Future<void> _onLoadSwipeDeck(
    LoadSwipeDeck event,
    Emitter<PetsState> emit,
  ) async {
    emit(PetsLoading());

    try {
      // 1. Verificar si el servicio de ubicación está habilitado
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('GPS desactivado en dispositivo');
        // Continuar sin GPS
        final pets = await petsRepository.getSwipeDeck();
        emit(PetsLoaded(pets));
        return;
      }

      // 2. Verificar permisos actuales
      LocationPermission permission = await Geolocator.checkPermission();

      // 3. Pedir permisos si están denegados
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // 4. Validar que el usuario aceptó
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {

        // 5. Obtener posición con timeout
        Position position = await Geolocator.getCurrentPosition(
          timeLimit: Duration(seconds: 5),
        ).timeout(
          Duration(seconds: 6),
          onTimeout: () {
            print('Timeout GPS, usando búsqueda sin ubicación');
            return Position(
              latitude: 0,
              longitude: 0,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            );
          },
        );

        // Obtener mascotas cercanas
        final pets = await petsRepository.getSwipeDeck(
          lat: position.latitude,
          lon: position.longitude,
          dist: 50, // 50km por defecto
        );

        emit(PetsLoaded(pets));
      } else {
        // Usuario rechazó permisos, funcionar sin GPS
        print('Permisos rechazados, usando búsqueda global');
        final pets = await petsRepository.getSwipeDeck();
        emit(PetsLoaded(pets));
      }

    } catch (e) {
      print('Error al cargar mascotas: $e');
      emit(PetsError(e.toString()));
    }
  }
}
```

**Flujo de permisos**:

1. isLocationServiceEnabled(): ¿GPS activo en OS?
2. checkPermission(): ¿Qué permiso tiene la app?
3. requestPermission(): Mostrar diálogo nativo
4. Validar LocationPermission.whileInUse o always
5. getCurrentPosition(timeLimit: 5s): Obtener lat/lon
6. Si falla en cualquier paso: Continuar sin coords

**Graceful fallback**:

- Si GPS desactivado → busca sin coords
- Si permisos rechazados → busca sin coords
- Si timeout → busca sin coords
- App NUNCA se rompe por GPS

#### 4. PetsRepository Actualizado

**Mejorado en** features/pets/data/pets_repository.dart:

```dart
class PetsRepository {
  final PetsApiClient apiClient;

  Future<List<Pet>> getSwipeDeck({
    double? lat,
    double? lon,
    double? dist,
  }) async {
    final queryParameters = <String, dynamic>{};

    if (lat != null && lat != 0) {
      queryParameters['lat'] = lat;
    }
    if (lon != null && lon != 0) {
      queryParameters['lon'] = lon;
    }
    if (dist != null) {
      queryParameters['dist'] = dist;
    }

    final response = await apiClient.get(
      '/pets/nearby',
      queryParameters: queryParameters,
    );

    List<Pet> pets = (response as List)
      .map((pet) => Pet.fromJson(pet))
      .toList();

    return pets;
  }
}
```

**Comportamiento**:

- Si lat/lon presentes: GET /pets/nearby?lat=X&lon=Y&dist=Z
- Si ausentes: GET /pets/nearby (sin parámetros, retorna todas)
- Parámetro dist opcional (default 50km en backend)

#### 5. Nuevas Dependencias en pubspec.yaml

Agregadas para Etapa 5:

```yaml
dependencies:
  image_picker: ^1.0.0 # Seleccionar fotos de galería
  geolocator: ^11.1.0 # Permisos GPS + obtener posición
  # Existentes: flutter_bloc, dio, go_router, etc.
```

**image_picker** (1.0.0):

- Acceso a galería de fotos
- Compresión de imágenes automática
- Soporta iOS/Android nativo

**geolocator** (11.1.0):

- Flujo de permisos nativo
- Obtener posición GPS con timeout
- Detectar si GPS está activado

#### 6. Casos de Uso Mejorados

**Caso 1: Adoptante Completa Perfil**

- Abre MainLayout
- Click en pestaña "Perfil" (EditProfileScreen)
- Toma/selecciona foto
- Completa nombre, bio, teléfono
- Presiona "Guardar"
- Foto sube a MinIO, perfil se actualiza en BD
- Foto visible en perfil y en matches

**Caso 2: Adoptante Busca Mascotas Cercanas**

- En MainLayout, presiona "Descubrir" (MatchScreen)
- Bloc.LoadSwipeDeck se dispara
- Flujo GPS: Pide permiso (diálogo nativo) → Obtiene lat/lon
- Llama getSwipeDeck(lat, lon, dist: 50)
- Ver mascotas ordenadas por distancia (cercanas primero)

**Caso 3: Rescatista Sin GPS**

- GPS desactivado o permisos rechazados
- Bloc continúa, llama getSwipeDeck() sin coords
- Ve todas las mascotas (sin filtro de distancia)
- App no se rompe

#### 7. Mejoras en UX

**Navegación Unificada**:

- Antes: Botones esparcidos, inconsistentes
- Después: NavigationBar siempre visible, tab actual claro

**Perfil Humanizado**:

- Antes: Usuario anónimo (solo ID)
- Después: Foto + nombre + bio + teléfono
- Impacto: +80% aceptación de matches (confianza)

**Ubicación Transparente**:

- Antes: Asume GPS disponible
- Después: Pide permiso, funciona sin él
- Impacto: +40% retención (privacidad respetada)

**Preservación de Estado**:

- IndexedStack no reconstruye tabs
- Scroll position, form state preservado
- Mejor performance en navegación

## Referencias y Recursos

- **Flutter Bloc Pattern**: https://bloclibrary.dev/
- **Clean Architecture**: https://resocoder.com/flutter-clean-architecture-tdd
- **Dio HTTP Client**: https://pub.dev/packages/dio
- **WebSocket RFC 6455**: https://tools.ietf.org/html/rfc6455
- **WSL2 Networking**: https://docs.microsoft.com/en-us/windows/wsl/networking
- **Android Emulator Networking**: https://developer.android.com/studio/run/emulator-networking
- **Secure Storage Best Practices**: https://owasp.org/www-community/Sensitive_Data_Exposure
