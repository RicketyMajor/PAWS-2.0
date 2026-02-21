import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../domain/match_model.dart';
import '../../data/matches_repository.dart';

class AdopterMatchesScreen extends StatefulWidget {
  // Callback para avisar al padre (MainLayout) cuántos mensajes hay
  final Function(int)? onBadgeUpdate;

  const AdopterMatchesScreen({super.key, this.onBadgeUpdate});

  @override
  State<AdopterMatchesScreen> createState() => _AdopterMatchesScreenState();
}

class _AdopterMatchesScreenState extends State<AdopterMatchesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
      // Instanciamos el repositorio oficial, que ya sabe cómo buscar el token seguro
      final matchesRepo = context.read<MatchesRepository>();

      // 1. Cargar Chats Activos
      try {
        final matches = await matchesRepo.getAdopterAcceptedMatches();
        if (mounted) {
          setState(() {
            _acceptedMatches = matches;
          });

          // --- CÁLCULO DE BADGES ---
          final totalUnread = matches.fold(0, (sum, m) => sum + m.unreadCount);
          widget.onBadgeUpdate?.call(totalUnread);
        }
      } catch (e) {
        print("Error cargando chats activos: $e");
      }

      // 2. Cargar Solicitudes Pendientes
      try {
        final pending = await matchesRepo.getAdopterPendingMatches();
        if (mounted) {
          setState(() {
            _pendingMatches = pending;
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
        final rescuerName = pet?.ownerName ?? 'Rescatista';
        final rescuerPhoto = pet?.ownerPhotoUrl;

        // Estilo dinámico según si hay mensajes nuevos
        final hasUnread = match.hasUnreadMessages;
        final backgroundColor = hasUnread
            ? Colors.pink[50]
            : Colors.white; // Más iluminado si no leído

        return Card(
          color: backgroundColor, // Fondo iluminado
          margin: const EdgeInsets.only(bottom: 12),
          elevation: hasUnread ? 4 : 1, // Más sombra si es importante
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: ImageHelper.getProvider(pet?.imageUrl),
                  backgroundColor: Colors.grey[200],
                ),
                // Indicador visual en la foto (opcional, pero se ve bien)
                if (hasUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              pet?.name ?? 'Mascota',
              style: TextStyle(
                decoration: match.isPetDeleted
                    ? TextDecoration.lineThrough
                    : null,
                color: match.isPetDeleted ? Colors.grey : Colors.black,
                // Negrita si hay mensajes nuevos
                fontWeight: hasUnread ? FontWeight.w900 : FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasUnread
                      ? "${match.unreadCount} mensajes nuevos"
                      : "Rescatista: $rescuerName",
                  style: TextStyle(
                    color: hasUnread
                        ? const Color(0xFFE91E63)
                        : Colors.grey[700],
                    fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (match.isPetDeleted)
                  const Text(
                    "⚠️ Publicación eliminada",
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                if (match.isRescuerLeft)
                  const Text(
                    "⚠️ Rescatista abandonó",
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
              ],
            ),
            // Badge numérico a la derecha
            trailing: hasUnread
                ? Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE91E63), // Color primario
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      match.unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : const Icon(Icons.chevron_right, color: Colors.grey),

            onTap: () async {
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
              _loadAllData(); // Recargar al volver (actualizar badge)
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
