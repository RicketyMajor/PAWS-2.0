import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/api_constants.dart'; // Para construir URL de foto
import '../../data/user_repository.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String? _currentPhotoUrl; // URL que viene del backend
  File? _newPhotoFile; // Foto nueva seleccionada del celular
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final repo = context.read<UserRepository>();
      final data = await repo.getProfile(); // GET /profile

      setState(() {
        _nameCtrl.text = data['name'] ?? '';
        _bioCtrl.text = data['bio'] ?? '';
        _phoneCtrl.text = data['phone'] ?? '';
        _currentPhotoUrl = data['photo_url'];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _newPhotoFile = File(picked.path);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final repo = context.read<UserRepository>();
      String finalPhotoUrl = _currentPhotoUrl ?? "";

      // 1. Si hay foto nueva, la subimos primero
      if (_newPhotoFile != null) {
        finalPhotoUrl = await repo.uploadProfilePicture(_newPhotoFile!);
      }

      // 2. Actualizamos el perfil con los textos y la URL (nueva o vieja)
      await repo.updateProfile(
        name: _nameCtrl.text,
        bio: _bioCtrl.text,
        phone: _phoneCtrl.text,
        photoUrl: finalPhotoUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("¡Perfil actualizado con éxito! 🎉")),
        );
        Navigator.pop(context, true); // Volvemos atrás indicando éxito
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Editar Perfil"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _save,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // --- FOTO DE PERFIL ---
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: _getAvatarImage(),
                            child: _getAvatarChild(),
                          ),
                          const CircleAvatar(
                            backgroundColor: Colors.blue,
                            radius: 18,
                            child: Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- CAMPOS DE TEXTO ---
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Nombre Completo",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (v) => v!.isEmpty ? "Campo requerido" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bioCtrl,
                      decoration: const InputDecoration(
                        labelText: "Biografía (Cuéntanos de ti)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                        hintText:
                            "Ej: Tengo patio grande y amo salir a correr...",
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: "Teléfono / WhatsApp",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  ImageProvider? _getAvatarImage() {
    if (_newPhotoFile != null) {
      return FileImage(_newPhotoFile!);
    }
    if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      // Manejar URL completa o relativa
      String url = _currentPhotoUrl!;
      if (!url.startsWith('http')) {
        url = '${ApiConstants.baseUrl}$url';
      }
      return NetworkImage(url);
    }
    return null;
  }

  Widget _getAvatarChild() {
    if (_newPhotoFile == null &&
        (_currentPhotoUrl == null || _currentPhotoUrl!.isEmpty)) {
      return const Icon(Icons.person, size: 60, color: Colors.grey);
    }
    return const SizedBox();
  }
}
