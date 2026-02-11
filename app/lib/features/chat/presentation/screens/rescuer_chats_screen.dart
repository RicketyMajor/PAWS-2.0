import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../pets/data/matches_repository.dart';
import '../../../pets/domain/match_model.dart';
import 'chat_screen.dart';

class RescuerChatsScreen extends StatefulWidget {
  // Callback para actualizar badge global
  final Function(int)? onBadgeUpdate;

  const RescuerChatsScreen({super.key, this.onBadgeUpdate});

  @override
  State<RescuerChatsScreen> createState() => _RescuerChatsScreenState();
}

class _RescuerChatsScreenState extends State<RescuerChatsScreen> {
  // Ya no usamos FutureBuilder directamente para tener más control
  List<Match> _matches = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final matches = await context.read<MatchesRepository>().getRescuerChats();

      if (mounted) {
        setState(() {
          _matches = matches;
          _isLoading = false;
        });

        // --- CÁLCULO DE BADGES ---
        final totalUnread = matches.fold(0, (sum, m) => sum + m.unreadCount);
        widget.onBadgeUpdate?.call(totalUnread);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Chats Activos 💬"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFE91E63),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text("Error: $_error"));
    if (_matches.isEmpty)
      return const Center(child: Text("No tienes chats activos aún."));

    return ListView.builder(
      itemCount: _matches.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final match = _matches[index];
        final adopter = match.adopter;
        final pet = match.pet;

        final adopterName = adopter?.name ?? 'Usuario Desconocido';
        final adopterPhoto = adopter?.photoUrl;
        final petName = pet?.name ?? 'Mascota';

        // Lógica de "No Leído"
        final hasUnread = match.hasUnreadMessages;
        final backgroundColor = hasUnread ? Colors.pink[50] : Colors.white;

        return Card(
          color: backgroundColor, // Iluminado si hay nuevos
          elevation: hasUnread ? 3 : 1,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: Stack(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.purple[100],
                  backgroundImage: ImageHelper.getProvider(adopterPhoto),
                  child: (adopterPhoto == null || adopterPhoto.isEmpty)
                      ? Text(
                          adopterName.isNotEmpty
                              ? adopterName[0].toUpperCase()
                              : '?',
                        )
                      : null,
                ),
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
              adopterName,
              style: TextStyle(
                color: (match.isAdopterLeft || match.isPetDeleted)
                    ? Colors.grey
                    : Colors.black,
                decoration: (match.isAdopterLeft || match.isPetDeleted)
                    ? TextDecoration.lineThrough
                    : null,
                fontWeight: hasUnread ? FontWeight.w900 : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasUnread)
                  Text(
                    "${match.unreadCount} mensajes nuevos",
                    style: const TextStyle(
                      color: Color(0xFFE91E63),
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else if (match.isPetDeleted)
                  const Text(
                    "Has eliminado esta publicación",
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  )
                else if (match.isAdopterLeft)
                  const Text(
                    "El usuario abandonó el chat",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Text(
                    "Interesado en $petName",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
              ],
            ),
            trailing: hasUnread
                ? Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE91E63),
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
                : const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    matchId: match.id,
                    peerName: adopterName,
                    peerId: match.adopterId,
                    peerPhotoUrl: adopterPhoto,
                    isPetDeleted: match.isPetDeleted,
                    isPeerLeft: match.isAdopterLeft,
                    isRescuer: true,
                  ),
                ),
              );
              _loadChats(); // Recargar al volver para actualizar estado
            },
          ),
        );
      },
    );
  }
}
