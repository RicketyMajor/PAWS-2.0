import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../chat/presentation/screens/chat_screen.dart';

class AdopterMatchesScreen extends StatefulWidget {
  const AdopterMatchesScreen({super.key});

  @override
  State<AdopterMatchesScreen> createState() => _AdopterMatchesScreenState();
}

class _AdopterMatchesScreenState extends State<AdopterMatchesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Dio _dio = Dio();
  final _storage = const FlutterSecureStorage();

  List<dynamic> _acceptedMatches = [];
  List<dynamic> _pendingMatches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'jwt_token');
      final options = Options(headers: {'Authorization': 'Bearer $token'});

      // Hacemos las dos peticiones en paralelo
      final responses = await Future.wait([
        _dio.get(
          '${ApiConstants.baseUrl}/matches/mine',
          options: options,
        ), // Accepted
        _dio.get(
          '${ApiConstants.baseUrl}/matches/mine/pending',
          options: options,
        ), // Pending
      ]);

      if (mounted) {
        setState(() {
          _acceptedMatches = responses[0].data;
          _pendingMatches = responses[1].data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print("Error cargando matches: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Interacciones"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFE91E63),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFE91E63),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFE91E63),
          tabs: const [
            Tab(text: "Chats Activos"),
            Tab(text: "Enviados"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChatsList(), // Pestaña 1
                _buildPendingList(), // Pestaña 2
              ],
            ),
    );
  }

  // LISTA DE CHATS (Lo que ya tenías)
  Widget _buildChatsList() {
    if (_acceptedMatches.isEmpty) {
      return _buildEmptyState(
        "No tienes chats activos",
        Icons.chat_bubble_outline,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _acceptedMatches.length,
      itemBuilder: (context, index) {
        final match = _acceptedMatches[index];
        final pet = match['pet'];
        final rescuerName = pet['User']?['name'] ?? 'Rescatista';

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: _getPetImage(pet['photo_url']),
              child: pet['photo_url'] == null ? const Icon(Icons.pets) : null,
            ),
            title: Text(
              pet['name'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text("Rescatista: $rescuerName"),
            trailing: const Icon(Icons.send, color: Color(0xFFE91E63)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ChatScreen(matchId: match['id'], peerName: rescuerName),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // LISTA DE PENDIENTES (NUEVO)
  Widget _buildPendingList() {
    if (_pendingMatches.isEmpty) {
      return _buildEmptyState(
        "No tienes solicitudes pendientes",
        Icons.access_time,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingMatches.length,
      itemBuilder: (context, index) {
        final match = _pendingMatches[index];
        final pet = match['pet'];

        return Card(
          color: Colors.grey[50], // Un poco más oscuro para diferenciar
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: _getPetImage(pet['photo_url']),
              child: pet['photo_url'] == null ? const Icon(Icons.pets) : null,
            ),
            title: Text(pet['name']),
            subtitle: const Text("Esperando respuesta del rescatista..."),
            trailing: const Icon(Icons.hourglass_empty, color: Colors.orange),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  ImageProvider? _getPetImage(String? url) {
    if (url == null) return null;
    if (!url.startsWith('http')) {
      return NetworkImage('${ApiConstants.baseUrl}$url');
    }
    return NetworkImage(url);
  }
}
