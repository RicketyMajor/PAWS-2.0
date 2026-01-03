import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../../../core/presentation/widgets/smart_image.dart';

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
          // 1. CORRECCIÓN: Agregamos "?? []" para evitar la pantalla morada de error NULL
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
        final pet = match['pet'];

        // 2. CORRECCIÓN ROBUSTA DE LECTURA DE DATOS
        // Intentamos leer 'User' (Go default) o 'user' (si tienes tags json)
        final rescuerData = pet['User'] ?? pet['user'];

        final rescuerName = rescuerData?['name'] ?? 'Rescatista';

        // 3. CORRECCIÓN CRÍTICA DEL ID
        // GORM envía 'ID' (Mayúscula). Probamos ambas por seguridad.
        final rescuerId = rescuerData?['ID'] ?? rescuerData?['id'] ?? 0;

        // DEBUG: Imprimir en consola para verificar qué está llegando
        print("DEBUG CHECK: Nombre: $rescuerName, ID detectado: $rescuerId");

        return Card(
          child: ListTile(
            leading: SizedBox(
              width: 60,
              height: 60,
              child: SmartImage(
                pet['photo_url'],
                borderRadius: BorderRadius.circular(30), // Para hacerlo redondo
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
                    peerId: rescuerId, // Ahora sí enviamos el ID correcto
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

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
          color: Colors.grey[50],
          child: ListTile(
            leading: SizedBox(
              width: 60,
              height: 60,
              child: SmartImage(
                pet['photo_url'],
                borderRadius: BorderRadius.circular(30), // Para hacerlo redondo
              ),
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
