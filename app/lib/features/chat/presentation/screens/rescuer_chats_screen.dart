import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../pets/data/matches_repository.dart'; // Asegúrate de importar esto
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
    // Usamos el repositorio de matches para traer los chats
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
              final adopter = match['adopter'];
              final pet = match['pet'];

              // Datos para mostrar
              final adopterName = adopter?['name'] ?? 'Adoptante';
              final petName = pet?['name'] ?? 'Mascota';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple[100],
                    child: Text(adopterName[0].toUpperCase()),
                  ),
                  title: Text(adopterName),
                  subtitle: Text("Interesado en $petName"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Navegar al chat
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          matchId: match['id'],
                          peerName: adopterName, // Hablamos con el Adoptante
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
