import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart'; // <--- IMPORTANTE
import '../../../pets/data/matches_repository.dart';
import 'chat_screen.dart';

class RescuerChatsScreen extends StatefulWidget {
  const RescuerChatsScreen({super.key});

  @override
  State<RescuerChatsScreen> createState() => _RescuerChatsScreenState();
}

class _RescuerChatsScreenState extends State<RescuerChatsScreen> {
  late Future<List<dynamic>> _chatsFuture;

  @override
  void initState() {
    super.initState();
    _chatsFuture = context.read<MatchesRepository>().getRescuerChats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Chats Activos 💬"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFE91E63),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _chatsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final chats = snapshot.data ?? [];

          if (chats.isEmpty) {
            return const Center(child: Text("No tienes chats activos aún."));
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final match = chats[index];

              // Datos del Adoptante
              final adopter = match['Adopter'] ?? match['adopter'];
              final pet = match['Pet'] ?? match['pet'];

              final adopterName = adopter?['name'] ?? 'Adoptante';
              final petName = pet?['name'] ?? 'Mascota';
              final adopterId = adopter?['ID'] ?? adopter?['id'] ?? 0;

              // --- NUEVO: Foto del Adoptante ---
              final adopterPhoto = adopter?['photo_url'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple[100],
                    // Usamos ImageHelper para mostrar la foto real si existe
                    backgroundImage: ImageHelper.getProvider(adopterPhoto),
                    child: (adopterPhoto == null || adopterPhoto.isEmpty)
                        ? Text(
                            adopterName.isNotEmpty
                                ? adopterName[0].toUpperCase()
                                : '?',
                          )
                        : null,
                  ),
                  title: Text(adopterName),
                  subtitle: Text("Interesado en $petName"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (adopterId == 0) return;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          matchId: match['id'],
                          peerName: adopterName,
                          peerId: adopterId,
                          peerPhotoUrl: adopterPhoto, // <--- Enviamos la foto
                        ),
                      ),
                    );
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
