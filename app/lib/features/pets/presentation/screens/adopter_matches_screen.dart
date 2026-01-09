import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../domain/match_model.dart'; // Importamos Match

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

  // Ahora son Listas de Match, no dynamic
  List<Match> _acceptedMatches = [];
  List<Match> _pendingMatches = [];
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

      // Hacemos las peticiones por separado para depurar mejor
      // y usamos try-catch individual para que un error en Pendientes no oculte los Activos

      // 1. Cargar Chats Activos
      try {
        final resAccepted = await _dio.get(
          '${ApiConstants.baseUrl}/matches/adopter?status=accepted',
          options: options,
        );
        if (mounted) {
          setState(() {
            _acceptedMatches = (resAccepted.data as List)
                .map((json) => Match.fromJson(json))
                .toList();
          });
        }
      } catch (e) {
        print("Error cargando chats activos: $e");
      }

      // 2. Cargar Solicitudes Pendientes
      try {
        final resPending = await _dio.get(
          '${ApiConstants.baseUrl}/matches/adopter?status=pending',
          options: options,
        );

        // DEBUG: Ver qué llega del backend
        print("Respuesta Pendientes: ${resPending.data}");

        if (mounted) {
          setState(() {
            _pendingMatches = (resPending.data as List)
                .map((json) => Match.fromJson(json))
                .toList();
          });
        }
      } catch (e) {
        print("Error cargando pendientes: $e");
      }
    } catch (e) {
      print("Error general en AdopterMatches: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Solicitudes"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFE91E63),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFE91E63),
          tabs: const [
            Tab(text: "Chats Activos"),
            Tab(text: "Pendientes"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildAcceptedList(), _buildPendingList()],
            ),
    );
  }

  Widget _buildAcceptedList() {
    if (_acceptedMatches.isEmpty) {
      return _buildEmptyState(
        "No tienes chats activos",
        Icons.chat_bubble_outline,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _acceptedMatches.length,
      itemBuilder: (context, index) {
        final match = _acceptedMatches[index];
        final pet = match.pet;

        // Datos del Peer (En este caso, el dueño de la mascota/Rescatista)
        final rescuerName = pet?.ownerName ?? 'Rescatista';
        final rescuerPhoto = pet?.ownerPhotoUrl;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              radius: 28,
              backgroundImage: ImageHelper.getProvider(
                pet?.imageUrl,
              ), // Mostramos foto mascota
            ),
            title: Text(
              pet?.name ?? 'Mascota',
              style: TextStyle(
                // Tachado si la mascota se borró
                decoration: match.isPetDeleted
                    ? TextDecoration.lineThrough
                    : null,
                color: match.isPetDeleted ? Colors.grey : Colors.black,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Rescatista: $rescuerName"),
                if (match.isPetDeleted)
                  const Text(
                    "Publicación eliminada",
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                if (match.isRescuerLeft)
                  const Text(
                    "Rescatista abandonó",
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
            trailing: const Icon(Icons.message, color: Color(0xFFE91E63)),
            onTap: () async {
              // <--- 1. Agregamos async
              // 2. Esperamos (await) a que el usuario regrese del chat
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    matchId: match.id,
                    peerName: rescuerName,
                    peerId: pet?.ownerId ?? 0,
                    peerPhotoUrl: rescuerPhoto,
                    isPetDeleted: match.isPetDeleted,
                    isPeerLeft: match.isRescuerLeft,
                  ),
                ),
              );
              // 3. Al volver, recargamos la lista automáticamente
              _loadAllData();
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
      padding: const EdgeInsets.all(12),
      itemCount: _pendingMatches.length,
      itemBuilder: (context, index) {
        final match = _pendingMatches[index];
        final pet = match.pet;

        return Card(
          color: Colors.grey[50],
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: ImageHelper.getImage(
                pet?.imageUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(
              pet?.name ?? 'Sin Nombre',
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
          Text(msg, style: TextStyle(color: Colors.grey[600], fontSize: 16)),
        ],
      ),
    );
  }
}
