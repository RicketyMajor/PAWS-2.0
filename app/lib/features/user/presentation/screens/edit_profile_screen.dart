import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/image_helper.dart';
import '../../data/user_repository.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // --- CONTROLADORES BÁSICOS ---
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // --- ESTADO NUEVOS CAMPOS (Valores por defecto) ---
  String _housingType = 'House';
  String _housingOwnership = 'Owned';
  bool _hasYard = false;
  bool _hasFence = false;
  String _familyComposition = 'Single';
  String _otherPets = 'None';
  String _timeAvailability = 'Medium';
  String _experience = 'Beginner';

  String? _currentPhotoUrl;
  File? _newPhotoFile;

  bool _isLoading = true;
  bool _isEditing = false; // Modo Lectura/Edición

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
          // Datos Básicos
          _nameCtrl.text = data['name'] ?? '';
          _bioCtrl.text = data['bio'] ?? '';
          _phoneCtrl.text = data['phone'] ?? '';
          _currentPhotoUrl = data['photo_url'];

          // Datos Vivienda (Con validación de nulos)
          _housingType = (data['housing_type']?.isNotEmpty ?? false)
              ? data['housing_type']
              : 'House';
          _housingOwnership = (data['housing_ownership']?.isNotEmpty ?? false)
              ? data['housing_ownership']
              : 'Owned';
          _hasYard = data['has_yard'] ?? false;
          _hasFence = data['has_fence'] ?? false;

          // Datos Estilo de Vida
          _familyComposition = (data['family_composition']?.isNotEmpty ?? false)
              ? data['family_composition']
              : 'Single';
          _otherPets = (data['other_pets']?.isNotEmpty ?? false)
              ? data['other_pets']
              : 'None';
          _timeAvailability = (data['time_availability']?.isNotEmpty ?? false)
              ? data['time_availability']
              : 'Medium';
          _experience = (data['experience']?.isNotEmpty ?? false)
              ? data['experience']
              : 'Beginner';

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
    if (!_isEditing) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _newPhotoFile = File(picked.path));
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
        // Nuevos Campos
        housingType: _housingType,
        housingOwnership: _housingOwnership,
        hasYard: _hasYard,
        hasFence: _hasFence,
        familyComposition: _familyComposition,
        otherPets: _otherPets,
        timeAvailability: _timeAvailability,
        experience: _experience,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isEditing = false;
          _currentPhotoUrl = finalPhotoUrl;
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- FOTO ---
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey[300],
                              backgroundImage: _newPhotoFile != null
                                  ? FileImage(_newPhotoFile!)
                                  : ImageHelper.getProvider(_currentPhotoUrl),
                            ),
                            if (_isEditing)
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
                    ),
                    const SizedBox(height: 24),

                    // --- DATOS BÁSICOS ---
                    const Text(
                      "Información Personal",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
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

                    const Divider(height: 40),

                    // --- VIVIENDA ---
                    const Text(
                      "Hogar y Entorno",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdown(
                            "Tipo de Vivienda",
                            _housingType,
                            ["House", "Apartment", "Parcel"],
                            (v) => setState(() => _housingType = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdown(
                            "Tenencia",
                            _housingOwnership,
                            ["Owned", "Rented"],
                            (v) => setState(() => _housingOwnership = v!),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text("Tiene Patio"),
                      value: _hasYard,
                      onChanged: _isEditing
                          ? (v) => setState(() => _hasYard = v)
                          : null,
                    ),
                    SwitchListTile(
                      title: const Text("Cerco/Mallas de Seguridad"),
                      value: _hasFence,
                      onChanged: _isEditing
                          ? (v) => setState(() => _hasFence = v)
                          : null,
                    ),

                    const Divider(height: 40),

                    // --- ESTILO DE VIDA ---
                    const Text(
                      "Familia y Rutina",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDropdown(
                      "Composición Familiar",
                      _familyComposition,
                      ["Single", "Couple", "Family w/Kids", "Seniors"],
                      (v) => setState(() => _familyComposition = v!),
                    ),
                    const SizedBox(height: 16),
                    _buildDropdown(
                      "Otras Mascotas",
                      _otherPets,
                      ["None", "Dogs", "Cats", "Both"],
                      (v) => setState(() => _otherPets = v!),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdown(
                            "Tiempo Libre",
                            _timeAvailability,
                            ["Low", "Medium", "High"],
                            (v) => setState(() => _timeAvailability = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdown(
                            "Experiencia",
                            _experience,
                            ["Beginner", "Intermediate", "Expert"],
                            (v) => setState(() => _experience = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
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
      enabled: _isEditing,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          color: _isEditing ? const Color(0xFFE91E63) : Colors.grey,
        ),
        border: const OutlineInputBorder(),
        filled: !_isEditing,
        fillColor: Colors.grey.shade50,
      ),
      maxLines: maxLines,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      validator: (v) => v!.isEmpty ? "Requerido" : null,
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    // Traducción simple para visualización
    String translate(String val) {
      switch (val) {
        case 'House':
          return 'Casa';
        case 'Apartment':
          return 'Depto';
        case 'Parcel':
          return 'Parcela';
        case 'Owned':
          return 'Propia';
        case 'Rented':
          return 'Arriendo';
        case 'Single':
          return 'Solo';
        case 'Couple':
          return 'Pareja';
        case 'Family w/Kids':
          return 'Familia c/Niños';
        case 'Seniors':
          return 'Adultos Mayores';
        case 'None':
          return 'Ninguna';
        case 'Both':
          return 'Ambos';
        case 'Low':
          return 'Poco';
        case 'Medium':
          return 'Medio';
        case 'High':
          return 'Mucho';
        case 'Beginner':
          return 'Principiante';
        case 'Intermediate':
          return 'Intermedio';
        case 'Expert':
          return 'Experto';
        default:
          return val;
      }
    }

    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: !_isEditing,
        fillColor: Colors.grey.shade50,
      ),
      value: value,
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(translate(e))))
          .toList(),
      onChanged: _isEditing ? onChanged : null, // Deshabilitar si no se edita
    );
  }
}
