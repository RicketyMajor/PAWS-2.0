import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// Importa tus pantallas
import '../../features/pets/presentation/screens/match_screen.dart';
import '../../features/pets/presentation/screens/adopter_matches_screen.dart';
import '../../features/user/presentation/screens/edit_profile_screen.dart';
import '../../features/pets/presentation/screens/rescuer_home_screen.dart';
import '../../features/pets/presentation/screens/match_requests_screen.dart';
import '../../features/chat/presentation/screens/rescuer_chats_screen.dart';

class MainLayoutScreen extends StatefulWidget {
  final String role;

  const MainLayoutScreen({super.key, required this.role});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _currentIndex = 0;

  // Contadores globales
  int _unreadChats = 0;
  int _pendingRequests = 0;

  DateTime? _lastPressedTime;

  // --- CALLBACKS PARA ACTUALIZAR BADGES DESDE LOS HIJOS ---

  void _updateUnreadCount(int count) {
    // Solo hacemos setState si el valor cambió para evitar re-renders infinitos
    if (_unreadChats != count) {
      setState(() {
        _unreadChats = count;
      });
    }
  }

  // (Opcional) Podrías implementar algo similar para _pendingRequests en MatchRequestsScreen

  @override
  Widget build(BuildContext context) {
    final isAdopter = widget.role == 'adopter';

    // Definición de Pantallas
    // AHORA PASAMOS EL CALLBACK
    final screens = isAdopter
        ? [
            const MatchScreen(),
            AdopterMatchesScreen(
              onBadgeUpdate: _updateUnreadCount,
            ), // <-- Conectado
            const EditProfileScreen(),
          ]
        : [
            const RescuerHomeScreen(),
            RescuerChatsScreen(
              onBadgeUpdate: _updateUnreadCount,
            ), // <-- Conectado
            const MatchRequestsScreen(),
            const EditProfileScreen(),
          ];

    // Definición de Íconos con BADGES
    final items = isAdopter
        ? [
            const NavigationDestination(
              icon: Icon(Icons.pets),
              label: 'Descubrir',
            ),
            NavigationDestination(
              // Usamos el contador dinámico _unreadChats
              icon: _buildBadgedIcon(Icons.favorite, _unreadChats),
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
              // Usamos el contador dinámico _unreadChats
              icon: _buildBadgedIcon(Icons.chat, _unreadChats),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: _buildBadgedIcon(Icons.notifications, _pendingRequests),
              label: 'Solicitudes',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ];

    return WillPopScope(
      onWillPop: () async {
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return false;
        }
        final now = DateTime.now();
        if (_lastPressedTime == null ||
            now.difference(_lastPressedTime!) > const Duration(seconds: 2)) {
          _lastPressedTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Presiona otra vez para salir"),
              duration: Duration(seconds: 2),
            ),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: items,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE91E63).withOpacity(0.2),
        ),
      ),
    );
  }

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
