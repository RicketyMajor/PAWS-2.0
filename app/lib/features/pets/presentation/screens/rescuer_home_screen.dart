import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';
import 'create_pet_screen.dart';
import 'pet_detail_screen.dart';

/// The home screen for users with the "rescuer" role.
/// It displays a list of pets they have published.
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

  /// Fetches the list of pets owned by the current user from the repository.
  Future<void> _loadMyPets() async {
    setState(() => _isLoading = true);
    try {
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading pets: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Pets"),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: "Log Out",
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
          // Navigate to the create screen and reload the list when returning.
          await Navigator.push(context, MaterialPageRoute(builder: (context) => const CreatePetScreen()));
          _loadMyPets();
        },
        label: const Text("Publish Pet"),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFFE91E63),
      ),
    );
  }

  /// Builds the UI for when the rescuer has not published any pets.
  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 80, color: Colors.grey),
          SizedBox(height: 20),
          Text("You haven't published any pets yet."),
        ],
      ),
    );
  }

  /// Builds the list of pet cards.
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
              // Navigate to detail and check for a result (e.g., `true` if pet was deleted) to reload.
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PetDetailScreen(pet: pet)),
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
                  child: ImageHelper.getImage(pet.imageUrl, width: 60, height: 60, fit: BoxFit.cover),
                ),
              ),
              title: Text(pet.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("${pet.breed} • ${pet.age} years"),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: pet.status == 'available' ? Colors.green[100] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    pet.status == 'available' ? 'Available' : pet.status.capitalize(),
                    style: TextStyle(fontSize: 12, color: pet.status == 'available' ? Colors.green[800] : Colors.black54),
                  ),
                ),
              ]),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        );
      },
    );
  }
}

extension on String {
    String capitalize() {
      return "${this[0].toUpperCase()}${this.substring(1).toLowerCase()}";
    }
}
