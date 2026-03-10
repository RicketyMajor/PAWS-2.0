import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/pets_repository.dart';

/// A form screen for rescuers to create and publish a new pet profile.
class CreatePetScreen extends StatefulWidget {
  const CreatePetScreen({super.key});

  @override
  State<CreatePetScreen> createState() => _CreatePetScreenState();
}

class _CreatePetScreenState extends State<CreatePetScreen> {
  final _formKey = GlobalKey<FormState>();

  // --- Form Controllers & State ---
  final _nameController = TextEditingController();
  final _breedController = TextEditingController();
  final _ageController = TextEditingController();
  final _descController = TextEditingController();
  final _needsController = TextEditingController();
  
  String _selectedType = 'Dog';
  String _energyLevel = 'medium';
  bool _isLoading = false;

  // Health state
  bool _isVaccinated = false;
  bool _isSterilized = false;
  bool _isDewormed = false;

  // Lifestyle preferences
  bool _requiresYard = false;
  bool _goodWithKids = false;
  bool _goodWithDogs = false;

  // Image handling
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();

  /// Opens the device's image gallery to select multiple images.
  Future<void> _pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage(
      imageQuality: 70, // Compress to 70% quality.
      maxWidth: 1080,   // Standardize max width.
    );
    if (images.isNotEmpty) {
      setState(() {
        if (_selectedImages.length + images.length > 10) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Maximum of 10 photos allowed.")));
          return;
        }
        _selectedImages.addAll(images);
      });
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  /// Determines the current geographical position of the device.
  Future<Position?> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GPS is disabled.')));
      return null;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition();
  }

  /// Validates the form, gathers all data, and submits it to the repository.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please upload at least one photo.")));
      return;
    }
    setState(() => _isLoading = true);

    try {
      Position? position = await _determinePosition();
      // Use Santiago, Chile as a fallback location if GPS fails.
      double lat = position?.latitude ?? -33.4489;
      double lon = position?.longitude ?? -70.6693;

      if (position == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Using default location.")));
      }

      await context.read<PetsRepository>().createPet(
        name: _nameController.text,
        type: _selectedType,
        breed: _breedController.text,
        age: int.parse(_ageController.text),
        description: _descController.text,
        latitude: lat,
        longitude: lon,
        images: _selectedImages,
        isVaccinated: _isVaccinated,
        isSterilized: _isSterilized,
        isDewormed: _isDewormed,
        specialNeeds: _needsController.text,
        requiresYard: _requiresYard,
        goodWithKids: _goodWithKids,
        goodWithDogs: _goodWithDogs,
        energyLevel: _energyLevel,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pet published successfully!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Pet Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageSection(),
              const SizedBox(height: 20),
              
              // --- Basic Information Section ---
              const Text("Basic Information", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: "Name", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Required" : null),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: const InputDecoration(labelText: "Type", border: OutlineInputBorder()),
                    items: const [DropdownMenuItem(value: 'Dog', child: Text("Dog")), DropdownMenuItem(value: 'Cat', child: Text("Cat"))],
                    onChanged: (v) => setState(() => _selectedType = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(controller: _ageController, decoration: const InputDecoration(labelText: "Age", border: OutlineInputBorder()), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? "Required" : null),
                ),
              ]),
              const SizedBox(height: 10),
              TextFormField(controller: _breedController, decoration: const InputDecoration(labelText: "Breed", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Required" : null),
              const SizedBox(height: 10),
              TextFormField(controller: _descController, decoration: const InputDecoration(labelText: "Description", border: OutlineInputBorder()), maxLines: 3, validator: (v) => v!.isEmpty ? "Required" : null),
              
              const Divider(height: 40),

              // --- Health Section ---
              const Text("Health & Vet Info", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SwitchListTile(title: const Text("Vaccines up to date"), value: _isVaccinated, onChanged: (v) => setState(() => _isVaccinated = v)),
              SwitchListTile(title: const Text("Spayed/Neutered"), value: _isSterilized, onChanged: (v) => setState(() => _isSterilized = v)),
              SwitchListTile(title: const Text("Dewormed"), value: _isDewormed, onChanged: (v) => setState(() => _isDewormed = v)),
              TextFormField(controller: _needsController, decoration: const InputDecoration(labelText: "Special Needs (Optional)", hintText: "e.g., Chicken allergy, takes medication...", border: OutlineInputBorder(), prefixIcon: Icon(Icons.local_hospital))),
              
              const Divider(height: 40),

              // --- Lifestyle Section ---
              const Text("Lifestyle", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("Energy Level:"),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'low', label: Text('Low'), icon: Icon(Icons.weekend)),
                  ButtonSegment(value: 'medium', label: Text('Medium'), icon: Icon(Icons.directions_walk)),
                  ButtonSegment(value: 'high', label: Text('High'), icon: Icon(Icons.bolt)),
                ],
                selected: {_energyLevel},
                onSelectionChanged: (Set<String> newSelection) => setState(() => _energyLevel = newSelection.first),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(title: const Text("Good with kids"), value: _goodWithKids, onChanged: (v) => setState(() => _goodWithKids = v!)),
              CheckboxListTile(title: const Text("Good with other dogs"), value: _goodWithDogs, onChanged: (v) => setState(() => _goodWithDogs = v!)),
              CheckboxListTile(title: const Text("Requires a yard"), value: _requiresYard, onChanged: (v) => setState(() => _requiresYard = v!)),
              
              const SizedBox(height: 30),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.publish),
                      label: const Text("PUBLISH PET"),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: const Color(0xFFE91E63)),
                    ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the image selection and preview section.
  Widget _buildImageSection() {
    return Column(
      children: [
        if (_selectedImages.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length + (_selectedImages.length < 10 ? 1 : 0), // Show add button only if less than 10 images.
              itemBuilder: (context, index) {
                if (index == _selectedImages.length) {
                  return GestureDetector(
                    onTap: _pickImages,
                    child: Container(width: 100, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey)), child: const Icon(Icons.add_a_photo, color: Colors.grey)),
                  );
                }
                // Image thumbnail
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          // Use NetworkImage for web and FileImage for mobile.
                          image: kIsWeb ? NetworkImage(_selectedImages[index].path) as ImageProvider : FileImage(File(_selectedImages[index].path)) as ImageProvider,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(right: 4, top: 4, child: GestureDetector(onTap: () => _removeImage(index), child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 16, color: Colors.white)))),
                    if (index == 0)
                      Positioned(bottom: 0, left: 0, right: 8, child: Container(color: Colors.black54, padding: const EdgeInsets.symmetric(vertical: 2), child: const Text("COVER", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
                  ],
                );
              },
            ),
          )
        else
          // Placeholder for picking the first image.
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid)),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate, size: 50, color: Colors.grey), Text("Tap to upload photos (Max 10)")]),
            ),
          ),
      ],
    );
  }
}
