import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Imports de tus Repositorios
import 'features/auth/data/auth_repository.dart';
import 'features/pets/data/pets_repository.dart';
import 'features/chat/data/chat_repository.dart'; // <--- IMPORTANTE

// Import de pantalla inicial
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/pets/presentation/screens/match_screen.dart';

void main() {
  runApp(const PawsApp());
}

class PawsApp extends StatelessWidget {
  const PawsApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MultiRepositoryProvider inyecta los repositorios en TODA la app
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (context) => AuthRepository()),
        RepositoryProvider(create: (context) => PetsRepository()),
        RepositoryProvider(
          create: (context) => ChatRepository(),
        ), // <--- ¡AQUÍ FALTABA ESTE!
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
        // Lógica simple de arranque:
        // Idealmente verificaríamos token aquí para ir directo a MatchScreen,
        // pero por ahora ir al Login está bien.
        home: const LoginScreen(),
      ),
    );
  }
}
