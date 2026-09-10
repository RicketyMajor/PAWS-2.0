import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

void main() {
  runApp(const PawsApp());
}

/// The single source of truth for the app's look. Lives outside the widget so a
/// test can assert on it: the minimum touch targets below were measured on the
/// deployed app, not assumed, and nothing else would notice if they vanished.
final ThemeData pawsTheme = ThemeData(
  primarySwatch: Colors.pink,
  useMaterial3: true,
  // Web resolves adaptivePlatformDensity to compact, which shrinks every
  // button below the 44px minimum touch target: measured on the deployed
  // login screen at 393px, the primary button painted 39px tall and the
  // text buttons 32px, and a tap 5px above one did not register. The
  // minimum sizes are explicit rather than left to density arithmetic,
  // and they apply to every button in the app instead of one screen.
  visualDensity: VisualDensity.standard,
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(minimumSize: const Size(64, 48)),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
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
);

class PawsApp extends StatelessWidget {
  const PawsApp({super.key});

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
        RepositoryProvider(
          create: (context) =>
              SecurityRepository(authRepository: context.read<AuthRepository>()),
        ),
        RepositoryProvider(
          create: (context) =>
              ReviewsRepository(authRepository: context.read<AuthRepository>()),
        ),
      ],
      child: MaterialApp(
        title: 'PAWS',
        debugShowCheckedModeBanner: false,
        theme: pawsTheme,
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
