import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/image_helper.dart'; // <--- IMPORTANTE
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'jwt_token');
      final options = Options(headers: {'Authorization': 'Bearer $token'});

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
          _acceptedMatches = responses[0].data ?? [];
          _pendingMatches = responses[1].data ?? [];
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
              children: [_buildChatsList(), _buildPendingList()],
            ),
    );
  }

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
        final pet =
            match['pet'] ?? match['Pet']; // Robustez mayúsculas/minúsculas

        // Extraer datos del Rescatista (Dueño de la mascota)
        final rescuerData = pet['User'] ?? pet['user'];
        final rescuerName = rescuerData?['name'] ?? 'Rescatista';
        final rescuerId = rescuerData?['ID'] ?? rescuerData?['id'] ?? 0;

        // --- NUEVO: Extraer Foto del Rescatista ---
        final rescuerPhoto = rescuerData?['photo_url'];

        return Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              // Usamos ImageHelper para asegurar que la foto de la mascota se vea
              child: ImageHelper.getImage(
                pet['photo_url'],
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
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
                  builder: (_) => ChatScreen(
                    matchId: match['id'],
                    peerName: rescuerName,
                    peerId: rescuerId,
                    peerPhotoUrl: rescuerPhoto, // <--- Enviamos la foto al chat
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // --- TAB 2: LIKES ENVIADOS (PENDIENTES) ---
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
        final pet =
            match['pet'] ?? match['Pet']; // Robustez mayúsculas/minúsculas

        return Card(
          color: Colors.grey[50], // Color diferente para indicar "Espera"
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              // Aquí también aplicamos ImageHelper para que se vea la foto
              child: ImageHelper.getImage(
                pet['photo_url'],
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(
              pet['name'] ?? 'Sin Nombre',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              "Esperando respuesta...",
              style: TextStyle(color: Colors.orange),
            ),
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
}
