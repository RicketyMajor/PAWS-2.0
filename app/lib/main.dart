import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:jwt_decoder/jwt_decoder.dart'; // Importante para leer el rol

// Imports de tus Repositorios
import 'features/auth/data/auth_repository.dart';
import 'features/pets/data/pets_repository.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/user/data/user_repository.dart';
import 'features/pets/data/matches_repository.dart';

// Imports de Pantallas
import 'features/auth/presentation/screens/login_screen.dart';
import 'core/presentation/main_layout_screen.dart'; // Layout Principal
import 'features/admin/presentation/screens/admin_dashboard_screen.dart'; // Dashboard Admin

import 'features/admin/data/admin_repository.dart';
import 'features/security/data/security_repository.dart';
import 'features/reviews/data/reviews_repository.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Notificación en Segundo Plano: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print("Error inicializando Firebase: $e");
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
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await messaging.getToken();
      if (token != null) {
        print("FCM Token: $token");
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
        // CORRECCIÓN: En lugar de LoginScreen directo, usamos el verificador
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
    // Pequeño delay para que se vea el logo (opcional, mejora UX)
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    try {
      final authRepo = context.read<AuthRepository>();
      final token = await authRepo.getToken();

      if (token != null && !JwtDecoder.isExpired(token)) {
        // Token válido -> Redirigir según Rol
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
        // No hay token o expiró -> Login
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      // Error leyendo token -> Login
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
