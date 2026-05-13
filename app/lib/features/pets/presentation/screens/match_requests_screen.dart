import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/matches_repository.dart';
import '../../domain/match_model.dart'; // <--- Importamos el modelo Match
import '../../../../core/utils/image_helper.dart';
import '../../../user/presentation/screens/public_profile_screen.dart';

class MatchRequestsScreen extends StatefulWidget {
  const MatchRequestsScreen({super.key});

  @override
  State<MatchRequestsScreen> createState() => _MatchRequestsScreenState();
}

class _MatchRequestsScreenState extends State<MatchRequestsScreen> {
  // Cambiamos dynamic por Match
  late Future<List<Match>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  void _loadRequests() {
    setState(() {
      _requestsFuture = context.read<MatchesRepository>().getPendingRequests();
    });
  }

  Future<void> _respond(int matchId, bool accept) async {
    try {
      await context.read<MatchesRepository>().respondMatch(matchId, accept);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? "¡Match Aceptado! 🎉" : "Solicitud rechazada"),
          backgroundColor: accept ? Colors.green : Colors.grey,
        ),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Solicitudes de Adopción")),
      body: FutureBuilder<List<Match>>(
        // Tipado fuerte
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 60, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No tienes solicitudes pendientes",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final match = requests[index];
              final adopter = match.adopter;
              final pet = match.pet;

              // Datos seguros del adoptante
              final adopterName = adopter?.name ?? 'Usuario Desconocido';
              final petName = pet?.name ?? 'Mascota';

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.purple[50],
                        backgroundImage: ImageHelper.getProvider(
                          adopter?.photoUrl,
                        ),
                        child: (adopter?.photoUrl == null)
                            ? Text(
                                adopterName.isNotEmpty
                                    ? adopterName[0].toUpperCase()
                                    : '?',
                              )
                            : null,
                      ),
                      title: Text(
                        "$adopterName quiere adoptar a $petName",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text("Toca para ver perfil completo"),
                      onTap: () {
                        if (adopter != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PublicProfileScreen(user: adopter),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Error: Datos del usuario incompletos",
                              ),
                            ),
                          );
                        }
                      },
                    ),

                    // Botones de Acción
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _respond(match.id, false),
                            child: const Text(
                              "RECHAZAR",
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _respond(match.id, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("ACEPTAR"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
