import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';
import 'create_pet_screen.dart'; // La crearemos en el paso 2

class RescuerHomeScreen extends StatefulWidget {
  const RescuerHomeScreen({super.key});

  @override
  State<RescuerHomeScreen> createState() => _RescuerHomeScreenState();
}

class _RescuerHomeScreenState extends State<RescuerHomeScreen> {
  // En el futuro, esto debería ir en un BLoC (RescuerPetsBloc),
  // pero para avanzar rápido usaremos estado local + repositorio directo.
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
      // NOTA: Necesitaremos agregar 'getMyPets' al repositorio
      // Por ahora usaremos 'getPets' y filtraremos en memoria o backend
      final pets = await context.read<PetsRepository>().getPets();
      setState(() {
        _myPets =
            pets; // Idealmente el backend debería tener endpoint /pets/my-pets
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Mascotas Publicadas"),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              // Navegar al Login (Logout simple)
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
          // Navegar a crear mascota y recargar al volver
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
          const SizedBox(height: 10),
          Text(
            "¡Ayuda a un animal a encontrar hogar!",
            style: TextStyle(color: Colors.grey[600]),
          ),
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
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: pet.imageUrl != null
                  ? NetworkImage(pet.imageUrl!) // Asegurar URL absoluta en Repo
                  : null,
              child: pet.imageUrl == null
                  ? const Icon(Icons.image_not_supported)
                  : null,
            ),
            title: Text(
              pet.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text("${pet.breed} • ${pet.age} años"),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}
