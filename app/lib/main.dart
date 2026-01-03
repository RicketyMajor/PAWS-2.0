import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart'; // Importar
import 'package:firebase_messaging/firebase_messaging.dart'; // Importar

// Imports de tus Repositorios
import 'features/auth/data/auth_repository.dart';
import 'features/pets/data/pets_repository.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/user/data/user_repository.dart'; // Necesario para guardar token

// Import de pantalla inicial
import 'features/auth/presentation/screens/login_screen.dart';

// Importante: Handler de notificaciones en segundo plano debe ser top-level
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Notificación en Segundo Plano: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializar Firebase
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print("Error inicializando Firebase (¿Falta configuración?): $e");
  }

  runApp(const PawsApp());
}

class PawsApp extends StatefulWidget {
  const PawsApp({super.key});

  @override
  State<PawsApp> createState() => _PawsAppState();
}

class _PawsAppState extends State<PawsApp> {
  @override
  void initState() {
    super.initState();
    _setupFirebaseMessaging();
  }

  void _setupFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 2. Pedir Permisos
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('Permiso de notificaciones concedido');

      // 3. Obtener Token
      String? token = await messaging.getToken();
      if (token != null) {
        print("FCM Token: $token");
        // Aquí deberíamos guardarlo en el repositorio cuando el usuario se loguee.
        // Como no tenemos el contexto de Auth aquí, lo ideal es hacerlo en el LoginBloc
        // o en el HomeScreen. Por ahora, solo lo imprimimos para debug.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (context) => AuthRepository()),
        RepositoryProvider(create: (context) => PetsRepository()),
        RepositoryProvider(create: (context) => ChatRepository()),
        RepositoryProvider(create: (context) => UserRepository()), // Agregado
      ],
      child: MaterialApp(
        title: 'PAWS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.pink,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            backgroundColor: Colors.white,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.black),
            titleTextStyle: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}
