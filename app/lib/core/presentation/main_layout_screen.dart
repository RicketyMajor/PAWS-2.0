import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// Importa tus pantallas
import '../../features/pets/presentation/screens/match_screen.dart';
import '../../features/pets/presentation/screens/adopter_matches_screen.dart';
import '../../features/user/presentation/screens/edit_profile_screen.dart';
import '../../features/pets/presentation/screens/rescuer_home_screen.dart';
import '../../features/pets/presentation/screens/match_requests_screen.dart';
import '../../features/chat/presentation/screens/rescuer_chats_screen.dart';
import '../../features/user/data/user_repository.dart';
import '../../features/pets/data/matches_repository.dart';

class MainLayoutScreen extends StatefulWidget {
  final String role;

  const MainLayoutScreen({super.key, required this.role});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _currentIndex = 0;

  // Simulación de notificaciones (En una etapa futura esto vendría del Backend)
  int _unreadChats = 0;
  int _pendingRequests = 0;

  @override
  Widget build(BuildContext context) {
    final isAdopter = widget.role == 'adopter';

    // Definición de Pantallas (Igual que antes)
    final screens = isAdopter
        ? [
            const MatchScreen(),
            const AdopterMatchesScreen(),
            RepositoryProvider(
              create: (_) => UserRepository(),
              child: const EditProfileScreen(),
            ),
          ]
        : [
            const RescuerHomeScreen(),
            RepositoryProvider(
              create: (_) => MatchesRepository(),
              child: const RescuerChatsScreen(),
            ),
            RepositoryProvider(
              create: (_) => MatchesRepository(),
              child: const MatchRequestsScreen(),
            ),
            RepositoryProvider(
              create: (_) => UserRepository(),
              child: const EditProfileScreen(),
            ),
          ];

    // Definición de Íconos con BADGES
    final items = isAdopter
        ? [
            const NavigationDestination(
              icon: Icon(Icons.pets),
              label: 'Descubrir',
            ),
            NavigationDestination(
              icon: _buildBadgedIcon(
                Icons.favorite,
                _unreadChats,
              ), // Badge en Matches
              label: 'Matches',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ]
        : [
            const NavigationDestination(
              icon: Icon(Icons.home),
              label: 'Mascotas',
            ),
            NavigationDestination(
              icon: _buildBadgedIcon(
                Icons.chat,
                _unreadChats,
              ), // Badge en Chats
              label: 'Chats',
            ),
            NavigationDestination(
              icon: _buildBadgedIcon(
                Icons.notifications,
                _pendingRequests,
              ), // Badge en Solicitudes
              label: 'Solicitudes',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
            // Truco UX: Si entra a la pestaña, borramos la notificación visual
            if (isAdopter && index == 1) _unreadChats = 0;
            if (!isAdopter && index == 1) _unreadChats = 0;
            if (!isAdopter && index == 2) _pendingRequests = 0;
          });
        },
        destinations: items,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE91E63).withOpacity(0.2),
      ),
    );
  }

  // Widget Helper para crear el ícono con punto rojo
  Widget _buildBadgedIcon(IconData icon, int count) {
    if (count == 0) return Icon(icon);

    return Stack(
      children: [
        Icon(icon),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              count > 9 ? '9+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
