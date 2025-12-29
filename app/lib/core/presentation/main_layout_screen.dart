import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// Importa tus pantallas aquí
import '../../features/pets/presentation/screens/match_screen.dart';
import '../../features/pets/presentation/screens/adopter_matches_screen.dart';
import '../../features/user/presentation/screens/edit_profile_screen.dart';
import '../../features/pets/presentation/screens/rescuer_home_screen.dart';
import '../../features/pets/presentation/screens/match_requests_screen.dart';
import '../../features/chat/presentation/screens/rescuer_chats_screen.dart';
import '../../features/user/data/user_repository.dart'; // Para inyectar en perfil
import '../../features/pets/data/matches_repository.dart'; // Para inyectar en chats y solicitudes

class MainLayoutScreen extends StatefulWidget {
  final String role; // 'adopter' o 'rescuer'

  const MainLayoutScreen({super.key, required this.role});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _currentIndex = 0;

  // Definimos las pantallas para cada rol
  late final List<Widget> _adopterScreens;
  late final List<Widget> _rescuerScreens;

  // Íconos para la barra
  late final List<BottomNavigationBarItem> _adopterItems;
  late final List<BottomNavigationBarItem> _rescuerItems;

  @override
  void initState() {
    super.initState();
    _initializeScreens();
  }

  void _initializeScreens() {
    // --- ADOPTANTE ---
    _adopterScreens = [
      const MatchScreen(), // 0: Feed (Home)
      const AdopterMatchesScreen(), // 1: Matches/Chats
      RepositoryProvider(
        // 2: Perfil (Con inyección)
        create: (_) => UserRepository(),
        child: const EditProfileScreen(),
      ),
    ];

    _adopterItems = const [
      BottomNavigationBarItem(icon: Icon(Icons.pets), label: 'Descubrir'),
      BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Mis Matches'),
      BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
    ];

    // --- RESCATISTA ---
    // Nota: RescuerHomeScreen ahora solo debe mostrar la lista, sin el AppBar de navegación vieja
    _rescuerScreens = [
      const RescuerHomeScreen(), // 0: Mis Mascotas
      RepositoryProvider(
        // 1: Chats
        create: (_) => MatchesRepository(), // Asumiendo que tienes este import
        child: const RescuerChatsScreen(),
      ),
      RepositoryProvider(
        // 2: Solicitudes
        create: (_) => MatchesRepository(),
        child: const MatchRequestsScreen(),
      ),
      RepositoryProvider(
        // 3: Perfil
        create: (_) => UserRepository(),
        child: const EditProfileScreen(),
      ),
    ];

    _rescuerItems = const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Mis Mascotas'),
      BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
      BottomNavigationBarItem(
        icon: Icon(Icons.notifications),
        label: 'Solicitudes',
      ),
      BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isAdopter = widget.role == 'adopter';
    final screens = isAdopter ? _adopterScreens : _rescuerScreens;
    final items = isAdopter ? _adopterItems : _rescuerItems;

    return Scaffold(
      // IndexedStack mantiene el estado de las pantallas (no recarga al cambiar tab)
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        // Usamos NavigationBar (Material 3) que es más moderno que BottomNavigationBar
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: items.map((item) {
          return NavigationDestination(icon: item.icon, label: item.label!);
        }).toList(),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE91E63).withOpacity(0.2),
      ),
    );
  }
}
