import 'package:flutter/foundation.dart';
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

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Notificación en Segundo Plano: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }
  } catch (e) {
    print("⚠️ Advertencia: Firebase no se pudo inicializar: $e");
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
      if (Firebase.apps.isEmpty) return;
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        try {
          String? token = await messaging.getToken();
          if (token != null) print("FCM Token: $token");
        } catch (e) {
          print("Error obteniendo FCM Token (Normal en web dev): $e");
        }
      }
    } catch (e) {
      print("Error configurando FCM: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- AQUÍ ESTÁ LA MAGIA DE LA INYECCIÓN ---
    return MultiRepositoryProvider(
      providers: [
        // 1. Creamos el AuthRepository (El Padre de los Tokens)
        RepositoryProvider(create: (context) => AuthRepository()),

        // 2. Inyectamos AuthRepository en los demás
        RepositoryProvider(
          create: (context) =>
              PetsRepository(authRepository: context.read<AuthRepository>()),
        ),
        RepositoryProvider(
          create: (context) =>
              UserRepository(authRepository: context.read<AuthRepository>()),
        ),
        RepositoryProvider(
          create: (context) =>
              MatchesRepository(authRepository: context.read<AuthRepository>()),
        ),

        // Otros repos (Si alguno necesita Auth, haz lo mismo)
        RepositoryProvider(
          create: (context) =>
              ChatRepository(authRepository: context.read<AuthRepository>()),
        ),
        RepositoryProvider(
          create: (context) =>
              AdminRepository(authRepository: context.read<AuthRepository>()),
        ),
        RepositoryProvider(create: (context) => SecurityRepository()),
        RepositoryProvider(
          create: (context) =>
              ReviewsRepository(authRepository: context.read<AuthRepository>()),
        ),
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
