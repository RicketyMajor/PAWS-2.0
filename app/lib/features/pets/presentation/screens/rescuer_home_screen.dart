import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';
import 'create_pet_screen.dart';
import 'pet_detail_screen.dart';
import 'package:provider/provider.dart';

class RescuerHomeScreen extends StatefulWidget {
  const RescuerHomeScreen({super.key});

  @override
  State<RescuerHomeScreen> createState() => _RescuerHomeScreenState();
}

class _RescuerHomeScreenState extends State<RescuerHomeScreen> {
  List<Pet> _myPets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyPets();
  }

  Future<void> _loadMyPets() async {
    setState(() => _isLoading = true);
    try {
      // CORRECCIÓN: Usamos getMyPets() para traer solo las mías
      final pets = await context.read<PetsRepository>().getMyPets();

      if (mounted) {
        setState(() {
          _myPets = pets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error cargando mascotas: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Mascotas"),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: "Cerrar Sesión",
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _myPets.isEmpty
          ? _buildEmptyState()
          : _buildPetsList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreatePetScreen()),
          );
          _loadMyPets();
        },
        label: const Text("Publicar Mascota"),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFFE91E63),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.pets, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text("No has publicado mascotas aún"),
        ],
      ),
    );
  }

  Widget _buildPetsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myPets.length,
      itemBuilder: (context, index) {
        final pet = _myPets[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PetDetailScreen(pet: pet),
                ),
              );
              if (result == true && mounted) {
                _loadMyPets();
              }
            },
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: SizedBox(
                width: 60,
                height: 60,
                child: ClipOval(
                  child: ImageHelper.getImage(
                    pet.imageUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              title: Text(
                pet.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${pet.breed} • ${pet.age} años"),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: pet.status == 'available'
                          ? Colors.green[100]
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pet.status == 'available' ? 'Disponible' : pet.status,
                      style: TextStyle(
                        fontSize: 12,
                        color: pet.status == 'available'
                            ? Colors.green[800]
                            : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        );
      },
    );
  }
}
