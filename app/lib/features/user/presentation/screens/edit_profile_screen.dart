import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/image_helper.dart'; // <--- IMPORTA EL HELPER
import '../../data/user_repository.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String? _currentPhotoUrl;
  File? _newPhotoFile;

  bool _isLoading = true;
  bool _isEditing = false; // <--- NUEVO: Controla el modo edición

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final repo = context.read<UserRepository>();
      final data = await repo.getProfile();

      if (mounted) {
        setState(() {
          _nameCtrl.text = data['name'] ?? '';
          _bioCtrl.text = data['bio'] ?? '';
          _phoneCtrl.text = data['phone'] ?? '';
          _currentPhotoUrl = data['photo_url'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _pickImage() async {
    if (!_isEditing) return; // Solo permite cambiar foto en modo edición

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

      if (_newPhotoFile != null) {
        finalPhotoUrl = await repo.uploadProfilePicture(_newPhotoFile!);
      }

      await repo.updateProfile(
        name: _nameCtrl.text,
        bio: _bioCtrl.text,
        phone: _phoneCtrl.text,
        photoUrl: finalPhotoUrl,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isEditing = false; // Volver a modo lectura
          _currentPhotoUrl = finalPhotoUrl; // Actualizar URL local
          _newPhotoFile = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("¡Perfil actualizado!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Perfil"),
        actions: [
          // Botón Cambiante: Lápiz (Editar) o Check (Guardar)
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit),
            onPressed: _isLoading
                ? null
                : (_isEditing
                      ? _save
                      : () => setState(() => _isEditing = true)),
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
                            // Usamos el Helper para la imagen
                            backgroundImage: _newPhotoFile != null
                                ? FileImage(_newPhotoFile!)
                                : ImageHelper.getProvider(_currentPhotoUrl),
                          ),
                          if (_isEditing) // Solo muestra la camarita en modo edición
                            const CircleAvatar(
                              backgroundColor: Color(0xFFE91E63),
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

                    // --- CAMPOS (Solo lectura si !_isEditing) ---
                    _buildTextField(_nameCtrl, "Nombre Completo", Icons.person),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _bioCtrl,
                      "Biografía",
                      Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _phoneCtrl,
                      "Teléfono",
                      Icons.phone,
                      isPhone: true,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool isPhone = false,
  }) {
    return TextFormField(
      controller: ctrl,
      enabled: _isEditing, // <--- MAGIA: Se bloquea si no editamos
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          color: _isEditing ? const Color(0xFFE91E63) : Colors.grey,
        ),
        border: const OutlineInputBorder(),
        disabledBorder: OutlineInputBorder(
          // Borde más sutil en modo lectura
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        filled: !_isEditing,
        fillColor: Colors.grey.shade50,
      ),
      maxLines: maxLines,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      validator: (v) => v!.isEmpty ? "Requerido" : null,
    );
  }
}
