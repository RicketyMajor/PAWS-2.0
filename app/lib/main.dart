import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // <--- Importante
import 'core/constants/api_constants.dart'; // Asegúrate de que ruta sea correcta
import 'features/auth/data/auth_repository.dart'; // <--- Importante
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/pets/data/pets_repository.dart';

void main() {
  runApp(const PawsApp());
}

class PawsApp extends StatelessWidget {
  const PawsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      // <--- CAMBIAMOS A MULTI
      providers: [
        RepositoryProvider(create: (context) => AuthRepository()),
        RepositoryProvider(create: (context) => PetsRepository()), // <--- NUEVO
      ],
      child: MaterialApp(
        title: 'PAWS 2.0',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE91E63),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        // Ahora LoginScreen ya tendrá acceso al repositorio sin crearlo ella misma
        home: const LoginScreen(),
      ),
    );
  }
}
