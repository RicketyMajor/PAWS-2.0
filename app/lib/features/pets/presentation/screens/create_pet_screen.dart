import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/pets_repository.dart';
import 'package:flutter/foundation.dart'; // <--- Para usar kIsWeb

class CreatePetScreen extends StatefulWidget {
  const CreatePetScreen({super.key});

  @override
  State<CreatePetScreen> createState() => _CreatePetScreenState();
}

class _CreatePetScreenState extends State<CreatePetScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores Básicos
  final _nameController = TextEditingController();
  final _breedController = TextEditingController();
  final _ageController = TextEditingController();
  final _descController = TextEditingController();
  final _needsController = TextEditingController(); // Necesidades especiales

  // Estado
  String _selectedType = 'Dog';
  String _energyLevel = 'medium';
  bool _isLoading = false;

  // Salud
  bool _isVaccinated = false;
  bool _isSterilized = false;
  bool _isDewormed = false;

  // Preferencias
  bool _requiresYard = false;
  bool _goodWithKids = false;
  bool _goodWithDogs = false;

  // Imágenes
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImages() async {
    // Selección múltiple con compresión nativa y transcodificación automática
    final List<XFile> images = await _picker.pickMultiImage(
      imageQuality:
          70, // Comprime al 70% de calidad visual (imperceptible en celulares, pero reduce el peso a 300kb)
      maxWidth:
          1080, // Estandariza el ancho máximo (Ideal para Cloudinary y redes sociales)
      maxHeight: 1080, // Estandariza el alto máximo
    );
    if (images.isNotEmpty) {
      setState(() {
        // Límite de 10
        if (_selectedImages.length + images.length > 10) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Máximo 10 fotos permitidas")),
          );
          return;
        }
        _selectedImages.addAll(images);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<Position?> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('GPS desactivado.')));
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Sube al menos 1 foto")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      Position? position = await _determinePosition();
      double lat = position?.latitude ?? -33.4489;
      double lon = position?.longitude ?? -70.6693;

      if (position == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Usando ubicación por defecto")),
        );
      }

      final repo = context.read<PetsRepository>();

      await repo.createPet(
        name: _nameController.text,
        type: _selectedType,
        breed: _breedController.text,
        age: int.parse(_ageController.text),
        description: _descController.text,
        latitude: lat,
        longitude: lon,
        images: _selectedImages,

        // Nuevos Campos
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("¡Mascota publicada con éxito!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nueva Mascota")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageSection(),
              const SizedBox(height: 20),

              // --- DATOS BÁSICOS ---
              const Text(
                "Información Básica",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Nombre",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Requerido" : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: const InputDecoration(
                        labelText: "Tipo",
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Dog', child: Text("Perro")),
                        DropdownMenuItem(value: 'Cat', child: Text("Gato")),
                      ],
                      onChanged: (v) => setState(() => _selectedType = v!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _ageController,
                      decoration: const InputDecoration(
                        labelText: "Edad",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? "Requerido" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _breedController,
                decoration: const InputDecoration(
                  labelText: "Raza",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Requerido" : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: "Descripción",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (v) => v!.isEmpty ? "Requerido" : null,
              ),

              const Divider(height: 40),

              // --- SALUD ---
              const Text(
                "Salud & Veterinaria",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SwitchListTile(
                title: const Text("Vacunas al día"),
                value: _isVaccinated,
                onChanged: (v) => setState(() => _isVaccinated = v),
              ),
              SwitchListTile(
                title: const Text("Esterilizado/Castrado"),
                value: _isSterilized,
                onChanged: (v) => setState(() => _isSterilized = v),
              ),
              SwitchListTile(
                title: const Text("Desparasitado"),
                value: _isDewormed,
                onChanged: (v) => setState(() => _isDewormed = v),
              ),
              TextFormField(
                controller: _needsController,
                decoration: const InputDecoration(
                  labelText: "Necesidades Especiales (Opcional)",
                  hintText: "Ej: Alergia al pollo, toma medicamentos...",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.local_hospital),
                ),
              ),

              const Divider(height: 40),

              // --- COMPATIBILIDAD ---
              const Text(
                "Estilo de Vida",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text("Nivel de Energía:"),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'low',
                    label: Text('Bajo'),
                    icon: Icon(Icons.weekend),
                  ),
                  ButtonSegment(
                    value: 'medium',
                    label: Text('Medio'),
                    icon: Icon(Icons.directions_walk),
                  ),
                  ButtonSegment(
                    value: 'high',
                    label: Text('Alto'),
                    icon: Icon(Icons.bolt),
                  ),
                ],
                selected: {_energyLevel},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() => _energyLevel = newSelection.first);
                },
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                title: const Text("Apto para niños"),
                value: _goodWithKids,
                onChanged: (v) => setState(() => _goodWithKids = v!),
              ),
              CheckboxListTile(
                title: const Text("Se lleva bien con perros"),
                value: _goodWithDogs,
                onChanged: (v) => setState(() => _goodWithDogs = v!),
              ),
              CheckboxListTile(
                title: const Text("Requiere patio grande"),
                value: _requiresYard,
                onChanged: (v) => setState(() => _requiresYard = v!),
              ),

              const SizedBox(height: 30),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.publish),
                      label: const Text("PUBLICAR MASCOTA"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFE91E63),
                      ),
                    ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      children: [
        if (_selectedImages.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount:
                  _selectedImages.length + 1, // +1 para el botón de agregar
              itemBuilder: (context, index) {
                if (index == _selectedImages.length) {
                  // Botón Agregar al final
                  return GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: const Icon(Icons.add_a_photo, color: Colors.grey),
                    ),
                  );
                }

                // Miniatura
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          // --- ESTE ES EL CAMBIO MÁGICO ---
                          image: kIsWeb
                              ? NetworkImage(_selectedImages[index].path)
                                    as ImageProvider
                              : FileImage(File(_selectedImages[index].path))
                                    as ImageProvider,
                          // --------------------------------
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.red,
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (index == 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 8,
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: const Text(
                            "PORTADA",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          )
        else
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.shade400,
                  style: BorderStyle.values[1],
                ), // Dashed effect simulator
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, size: 50, color: Colors.grey),
                  Text("Toca para subir fotos (Máx 10)"),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
