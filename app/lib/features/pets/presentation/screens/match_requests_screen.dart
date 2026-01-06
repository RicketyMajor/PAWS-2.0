import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/matches_repository.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../user/domain/user_model.dart'; // <--- Importamos el modelo
import '../../../user/presentation/screens/public_profile_screen.dart'; // <--- Importamos la pantalla

class MatchRequestsScreen extends StatefulWidget {
  const MatchRequestsScreen({super.key});

  @override
  State<MatchRequestsScreen> createState() => _MatchRequestsScreenState();
}

class _MatchRequestsScreenState extends State<MatchRequestsScreen> {
  late Future<List<dynamic>> _requestsFuture;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? "¡Match Aceptado! 🎉" : "Solicitud rechazada"),
          backgroundColor: accept ? Colors.green : Colors.grey,
        ),
      );
      _loadRequests();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Solicitudes de Adopción")),
      body: FutureBuilder<List<dynamic>>(
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
              child: Text("No tienes solicitudes pendientes."),
            );
          }

          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              // Extraer datos crudos
              final adopterMap = req['adopter'];
              final petName = req['pet']?['name'] ?? 'Mascota';
              final matchId = req['id'];

              // Crear objeto User seguro
              User? adopter;
              if (adopterMap != null) {
                adopter = User.fromJson(adopterMap);
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundImage: ImageHelper.getProvider(
                          adopter?.photoUrl,
                        ),
                        child:
                            adopter?.photoUrl == null ||
                                adopter!.photoUrl.isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        "${adopter?.name ?? 'Usuario'} quiere adoptar a $petName",
                      ),
                      subtitle: const Text(
                        "Toca para ver perfil completo",
                        style: TextStyle(color: Colors.blue),
                      ),
                      onTap: () {
                        // --- AQUÍ LA MAGIA: Navegar al perfil ---
                        if (adopter != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  PublicProfileScreen(user: adopter!),
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
                    ButtonBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _respond(matchId, false),
                          child: const Text(
                            "RECHAZAR",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => _respond(matchId, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          child: const Text("ACEPTAR"),
                        ),
                      ],
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
