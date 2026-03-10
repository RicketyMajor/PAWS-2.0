import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'dart:convert';
import '../../features/chat/data/chat_repository.dart';

// Screen Imports
import '../../features/pets/presentation/screens/match_screen.dart';
import '../../features/pets/presentation/screens/adopter_matches_screen.dart';
import '../../features/user/presentation/screens/edit_profile_screen.dart';
import '../../features/pets/presentation/screens/rescuer_home_screen.dart';
import '../../features/pets/presentation/screens/match_requests_screen.dart';
import '../../features/chat/presentation/screens/rescuer_chats_screen.dart';


// =========================================================================
// Main Layout Widget
// =========================================================================

/// A stateful widget that provides the main UI structure (scaffold and navigation bar)
/// after a user has logged in. It displays different tabs based on the user's role.
class MainLayoutScreen extends StatefulWidget {
  final String role;

  const MainLayoutScreen({super.key, required this.role});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  // --- State Variables ---
  int _currentIndex = 0;
  int _unreadChats = 0;
  int _pendingRequests = 0;
  DateTime? _lastPressedTime; // For 'double press to exit' logic.
  StreamSubscription? _globalChatSub;

  @override
  void initState() {
    super.initState();
    _initGlobalWebSocket();
  }

  /// Initializes a global WebSocket listener to receive real-time updates,
  /// like new messages, to update notification badges.
  void _initGlobalWebSocket() async {
    final chatRepo = context.read<ChatRepository>();
    try {
      await chatRepo.connect(); // Establish the global WebSocket connection.
      _globalChatSub = chatRepo.messages.listen((data) {
        try {
          final decoded = jsonDecode(data);
          if (decoded['type'] == 'new_message') {
            setState(() {
              _unreadChats++; // Increment badge count on new message.
            });
          }
        } catch (e) {
          print("Error parsing global WebSocket data: $e");
        }
      });
    } catch (e) {
      print("Could not start global WebSocket listener: $e");
    }
  }

  @override
  void dispose() {
    _globalChatSub?.cancel(); // Clean up the subscription to prevent memory leaks.
    super.dispose();
  }

  // --- UI Update Callbacks ---

  /// Allows child widgets to update the unread chat count in the navigation bar.
  void _updateUnreadCount(int count) {
    if (_unreadChats != count) {
      setState(() {
        _unreadChats = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdopter = widget.role == 'adopter';

    // Define the screens available for each role.
    final screens = isAdopter
        ? [
            const MatchScreen(),
            AdopterMatchesScreen(onBadgeUpdate: _updateUnreadCount),
            const EditProfileScreen(),
          ]
        : [
            const RescuerHomeScreen(),
            RescuerChatsScreen(onBadgeUpdate: _updateUnreadCount),
            const MatchRequestsScreen(),
            const EditProfileScreen(),
          ];

    // Define the navigation bar items for each role, including badges.
    final items = isAdopter
        ? [
            const NavigationDestination(icon: Icon(Icons.pets), label: 'Discover'),
            NavigationDestination(icon: _buildBadgedIcon(Icons.favorite, _unreadChats), label: 'Matches'),
            const NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          ]
        : [
            const NavigationDestination(icon: Icon(Icons.home), label: 'Pets'),
            NavigationDestination(icon: _buildBadgedIcon(Icons.chat, _unreadChats), label: 'Chats'),
            NavigationDestination(icon: _buildBadgedIcon(Icons.notifications, _pendingRequests), label: 'Requests'),
            const NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          ];

    // WillPopScope handles the Android back button press.
    return WillPopScope(
      onWillPop: () async {
        // If not on the first tab, navigate to the first tab.
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return false;
        }
        // Implement "double press to exit" logic.
        final now = DateTime.now();
        if (_lastPressedTime == null || now.difference(_lastPressedTime!) > const Duration(seconds: 2)) {
          _lastPressedTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Press back again to exit"), duration: Duration(seconds: 2)),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        // Display only the currently selected screen from the list.
        body: screens[_currentIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          destinations: items,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE91E63).withOpacity(0.2),
        ),
      ),
    );
  }

  /// A helper widget to build an icon with a notification badge.
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
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              count > 9 ? '9+' : '$count',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
