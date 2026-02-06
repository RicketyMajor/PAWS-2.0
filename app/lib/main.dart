import 'package:flutter/foundation.dart'; // Para kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

// Imports de tus Repositorios
import 'features/auth/data/auth_repository.dart';
import 'features/pets/data/pets_repository.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/user/data/user_repository.dart';
import 'features/pets/data/matches_repository.dart';

// Imports de Pantallas
import 'features/auth/presentation/screens/login_screen.dart';
import 'core/presentation/main_layout_screen.dart';
import 'features/admin/presentation/screens/admin_dashboard_screen.dart';

import 'features/admin/data/admin_repository.dart';
import 'features/security/data/security_repository.dart';
import 'features/reviews/data/reviews_repository.dart';

// Handler simple para background (solo móvil)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Notificación en Segundo Plano: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- INICIALIZACIÓN ROBUSTA DE FIREBASE ---
  try {
    // Si tienes firebase_options.dart generado, úsalo aquí.
    // Si no, este bloque try-catch evitará que la app web explote al inicio.
    await Firebase.initializeApp();

    // Solo registramos el handler si no estamos en web para evitar errores de Service Worker faltantes
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }
  } catch (e) {
    print(
      "Advertencia: Firebase no se pudo inicializar (Normal en Web dev sin config): $e",
    );
    // La app continuará ejecutándose sin Firebase
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
    _setupFCM();
  }

  Future<void> _setupFCM() async {
    try {
      // Verificamos si Firebase está activo antes de llamar a Messaging
      if (Firebase.apps.isEmpty) return;

      FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Pedimos permisos con gracia
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // En Web, getToken requiere un VAPID key público, si no lo tienes, fallará.
        // Lo envolvemos en try-catch para que no moleste en consola.
        try {
          String? token = await messaging.getToken();
          if (token != null) {
            print("FCM Token: $token");
          }
        } catch (e) {
          print(
            "No se pudo obtener FCM Token (Probablemente falta configuración Web): $e",
          );
        }
      }
    } catch (e) {
      print("Error configurando FCM: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (context) => AuthRepository()),
        RepositoryProvider(create: (context) => PetsRepository()),
        RepositoryProvider(create: (context) => ChatRepository()),
        RepositoryProvider(create: (context) => UserRepository()),
        RepositoryProvider(create: (context) => MatchesRepository()),
        RepositoryProvider(create: (context) => AdminRepository()),
        RepositoryProvider(create: (context) => SecurityRepository()),
        RepositoryProvider(create: (context) => ReviewsRepository()),
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
        home: const AuthCheckScreen(),
      ),
    );
  }
}

// --- PANTALLA DE CARGA / VERIFICACIÓN DE SESIÓN ---
class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    try {
      final authRepo = context.read<AuthRepository>();
      final token = await authRepo.getToken();

      if (token != null && !JwtDecoder.isExpired(token)) {
        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
        String role = decodedToken['role'] ?? 'adopter';

        if (!mounted) return;

        if (role == 'admin') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainLayoutScreen(role: role)),
          );
        }
      } else {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.pets, size: 100, color: Color(0xFFE91E63)),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
