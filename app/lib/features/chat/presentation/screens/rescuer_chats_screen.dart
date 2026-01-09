import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../pets/data/matches_repository.dart';
import '../../../pets/domain/match_model.dart';
import 'chat_screen.dart';

class RescuerChatsScreen extends StatefulWidget {
  const RescuerChatsScreen({super.key});

  @override
  State<RescuerChatsScreen> createState() => _RescuerChatsScreenState();
}

class _RescuerChatsScreenState extends State<RescuerChatsScreen> {
  late Future<List<Match>> _chatsFuture;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  // Método extraído para poder llamarlo de nuevo
  void _loadChats() {
    setState(() {
      _chatsFuture = context.read<MatchesRepository>().getRescuerChats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Chats Activos 💬"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFE91E63),
      ),
      body: FutureBuilder<List<Match>>(
        future: _chatsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final matches = snapshot.data ?? [];

          if (matches.isEmpty) {
            return const Center(child: Text("No tienes chats activos aún."));
          }

          return ListView.builder(
            itemCount: matches.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final match = matches[index];
              final adopter = match.adopter;
              final pet = match.pet;

              final adopterName = adopter?.name ?? 'Usuario Desconocido';
              final adopterPhoto = adopter?.photoUrl;
              final petName = pet?.name ?? 'Mascota';

              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
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
                  title: Text(
                    adopterName,
                    style: TextStyle(
                      color: match.isAdopterLeft ? Colors.grey : Colors.black,
                      decoration: match.isAdopterLeft
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    match.isAdopterLeft
                        ? "El usuario abandonó el chat"
                        : "Interesado en $petName",
                    style: TextStyle(
                      color: match.isAdopterLeft
                          ? Colors.red[300]
                          : Colors.grey[600],
                      fontStyle: match.isAdopterLeft
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    // CAMBIO CLAVE: Esperamos el resultado de la navegación
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
                        ),
                      ),
                    );
                    // AL VOLVER, RECARGAMOS LA LISTA
                    _loadChats();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
