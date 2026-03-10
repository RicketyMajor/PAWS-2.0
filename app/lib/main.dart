import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

// Repositories
import 'features/auth/data/auth_repository.dart';
import 'features/pets/data/pets_repository.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/user/data/user_repository.dart';
import 'features/pets/data/matches_repository.dart';
import 'features/admin/data/admin_repository.dart';
import 'features/security/data/security_repository.dart';
import 'features/reviews/data/reviews_repository.dart';

// Screens
import 'features/auth/presentation/screens/login_screen.dart';
import 'core/presentation/main_layout_screen.dart';
import 'features/admin/presentation/screens/admin_dashboard_screen.dart';

// =========================================================================
// Firebase Background Handler
// =========================================================================

/// Handles incoming FCM messages when the app is in the background or terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, like Firestore,
  // make sure you call `initializeApp` before using them.
  print("Handling a background message: ${message.messageId}");
}

// =========================================================================
// Main Application Entry Point
// =========================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    // Set the background messaging handler for non-web platforms.
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    print("⚠️ Warning: Firebase could not be initialized: $e");
  }

  runApp(const PawsApp());
}

// =========================================================================
// Root Application Widget
// =========================================================================

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

  /// Sets up Firebase Cloud Messaging, requesting permissions and getting the token.
  Future<void> _setupFCM() async {
    try {
      if (Firebase.apps.isEmpty) return; // Don't run if Firebase isn't initialized.
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
          print("Error getting FCM Token (this is normal in web dev): $e");
        }
      }
    } catch (e) {
      print("Error setting up FCM: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use MultiRepositoryProvider to provide repository instances to the entire app.
    return MultiRepositoryProvider(
      providers: [
        // AuthRepository is at the top as other repositories depend on it for tokens.
        RepositoryProvider(create: (context) => AuthRepository()),

        // Other repositories are created here, reading the AuthRepository from the context.
        RepositoryProvider(create: (context) => PetsRepository(authRepository: context.read<AuthRepository>())),
        RepositoryProvider(create: (context) => UserRepository(authRepository: context.read<AuthRepository>())),
        RepositoryProvider(create: (context) => MatchesRepository(authRepository: context.read<AuthRepository>())),
        RepositoryProvider(create: (context) => ChatRepository(authRepository: context.read<AuthRepository>())),
        RepositoryProvider(create: (context) => AdminRepository(authRepository: context.read<AuthRepository>())),
        RepositoryProvider(create: (context) => SecurityRepository()),
        RepositoryProvider(create: (context) => ReviewsRepository(authRepository: context.read<AuthRepository>())),
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
        // The initial screen checks for an existing session.
        home: const AuthCheckScreen(),
      ),
    );
  }
}

// =========================================================================
// Authentication Check Screen (Splash/Loading)
// =========================================================================

/// This widget checks for a valid session token and navigates the user
/// to the appropriate screen (Login, Main, or Admin).
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
    // Brief delay to show splash screen
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    try {
      final authRepo = context.read<AuthRepository>();
      final token = await authRepo.getToken();

      if (token != null && !JwtDecoder.isExpired(token)) {
        // If token is valid, decode it to get the user's role.
        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
        String role = decodedToken['role'] ?? 'adopter';

        if (!mounted) return;

        // Navigate based on role.
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
        // If no token or expired, navigate to Login.
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      // On any error, default to the Login screen for safety.
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // A simple loading indicator UI.
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
