import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

// --- Imports de Utilidades y Datos ---
import '../../../../core/utils/image_helper.dart';
import '../../data/user_repository.dart';
import '../../domain/user_model.dart';

// --- Imports de Pantallas Relacionadas ---
import '../../../security/presentation/screens/blacklist_search_screen.dart';
import '../../../reviews/presentation/screens/user_reviews_screen.dart';
import '../../../auth/presentation/screens/register_screen.dart';
import '../../../../core/presentation/main_layout_screen.dart';
import '../../../auth/presentation/screens/login_screen.dart'; // <--- NECESARIO PARA REDIRIGIR AL LOGOUT

// --- Import del Repositorio de Autenticación (Para Switch y Logout) ---
import '../../../auth/data/auth_repository.dart';
import 'package:flutter/foundation.dart'; // <--- Para usar kIsWeb

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
  final ImagePicker _picker = ImagePicker();

  // --- OPCIONES VÁLIDAS ---
  static const List<String> _housingTypesOptions = [
    "House",
    "Apartment",
    "Parcel",
  ];
  static const List<String> _ownershipOptions = ["Owned", "Rented"];
  static const List<String> _familyOptions = [
    "Single",
    "Couple",
    "Family w/Kids",
    "Seniors",
  ];
  static const List<String> _petsOptions = ["None", "Dogs", "Cats", "Both"];
  static const List<String> _timeOptions = ["Low", "Medium", "High"];
  static const List<String> _expOptions = [
    "Beginner",
    "Intermediate",
    "Expert",
  ];

  // --- ESTADO NUEVOS CAMPOS ---
  String _housingType = _housingTypesOptions[0];
  String _housingOwnership = _ownershipOptions[0];
  bool _hasYard = false;
  bool _hasFence = false;
  String _familyComposition = _familyOptions[0];
  String _otherPets = _petsOptions[0];
  String _timeAvailability = _timeOptions[1]; // Medium
  String _experience = _expOptions[0];

  // --- ESTADO DE REPUTACIÓN E IDENTIDAD ---
  double _averageRating = 0.0;
  int _reviewCount = 0;
  int _userId = 0;

  // Variables para Cambio de Rol
  String _currentRole = 'adopter';
  String _currentEmail = '';
  String _currentRun = '';

  String? _currentPhotoUrl;
  XFile? _newPhotoFile;

  bool _isLoading = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // Función auxiliar para asegurar que el valor exista en la lista
  String _validateOption(String? value, List<String> options) {
    if (value != null && options.contains(value)) {
      return value;
    }
    return options[0];
  }

  Future<void> _loadProfile() async {
    try {
      final repo = context.read<UserRepository>();
      final data = await repo.getProfile();
      final user = User.fromJson(data);

      if (mounted) {
        setState(() {
          // Datos Identificación
          _userId = user.id;
          _currentRole = user.role;
          _currentEmail = user.email;
          _currentRun = data['run'] ?? '';

          // Datos Reputación
          _averageRating = user.averageRating;
          _reviewCount = user.reviewCount;

          // Datos Básicos
          _nameCtrl.text = user.name;
          _bioCtrl.text = user.bio;
          _phoneCtrl.text = user.phone;
          _currentPhotoUrl = user.photoUrl;

          // Datos Vivienda
          _housingType = _validateOption(
            user.housingType,
            _housingTypesOptions,
          );
          _housingOwnership = _validateOption(
            user.housingOwnership,
            _ownershipOptions,
          );
          _hasYard = user.hasYard;
          _hasFence = user.hasFence;

          // Datos Estilo de Vida
          _familyComposition = _validateOption(
            user.familyComposition,
            _familyOptions,
          );
          _otherPets = _validateOption(user.otherPets, _petsOptions);
          _timeAvailability = _validateOption(
            user.timeAvailability,
            _timeOptions,
          );
          _experience = _validateOption(user.experience, _expOptions);

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        print("Error cargando perfil: $e");
      }
    }
  }

  // --- LÓGICA DE CERRAR SESIÓN (NUEVO) ---
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cerrar Sesión"),
        content: const Text("¿Estás seguro que deseas cerrar sesión?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // Cierra el diálogo

              // 1. Ejecuta Logout del Repo (Borra el token del almacenamiento)
              await context.read<AuthRepository>().logout();

              if (!mounted) return;

              // 2. Navega al Login y elimina todo el historial de pantallas previas
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(
              "Sí, cerrar",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // --- LÓGICA DE CAMBIO DE ROL ---
  Future<void> _handleSwitchRole() async {
    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthRepository>();
      final newUserMap = await authRepo.switchRole();

      if (newUserMap != null) {
        final newRole = newUserMap['role'];
        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MainLayoutScreen(role: newRole)),
          (route) => false,
        );
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showCreateAccountDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCreateAccountDialog() {
    final targetRoleName = _currentRole == 'adopter'
        ? 'Rescatista'
        : 'Adoptante';
    final targetRoleCode = _currentRole == 'adopter' ? 'rescuer' : 'adopter';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Activar modo $targetRoleName"),
        content: Text(
          "Aún no tienes un perfil de $targetRoleName asociado a tu cuenta.\n\n"
          "¿Quieres activarlo ahora usando tus mismos datos (RUT y Email)?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RegisterScreen(
                    initialName: _nameCtrl.text,
                    initialEmail: _currentEmail,
                    initialRun: _currentRun,
                    initialRole: targetRoleCode,
                  ),
                ),
              );
            },
            child: const Text("Sí, activar"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _newPhotoFile = pickedFile;
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
    final targetRoleLabel = _currentRole == 'adopter'
        ? 'Modo Rescatista'
        : 'Modo Adoptante';
    final targetColor = _currentRole == 'adopter'
        ? Colors.purple
        : Colors.orange;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Perfil"),
        actions: [
          // 1. Botón Editar (Se mantiene igual)
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit),
            onPressed: _isLoading
                ? null
                : (_isEditing
                      ? _save
                      : () => setState(() => _isEditing = true)),
          ),

          // 2. Botón de Opciones (Engranaje) - NUEVO
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings, color: Colors.blueGrey),
            onSelected: (value) {
              if (value == 'logout') {
                _confirmLogout();
              } else if (value == 'blacklist') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BlacklistSearchScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'blacklist',
                child: Row(
                  children: [
                    Icon(Icons.security, size: 20, color: Colors.blueGrey),
                    SizedBox(width: 10),
                    Text("Consultar Blacklist"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, size: 20, color: Colors.red),
                    SizedBox(width: 10),
                    Text("Cerrar Sesión", style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
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
                                  ? (kIsWeb
                                            ? NetworkImage(_newPhotoFile!.path)
                                            : FileImage(
                                                File(_newPhotoFile!.path),
                                              ))
                                        as ImageProvider
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
                    const SizedBox(height: 16),

                    // --- BOTÓN DE CAMBIO DE ROL ---
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: targetColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _handleSwitchRole,
                        icon: const Icon(Icons.swap_horiz),
                        label: Text("Cambiar a $targetRoleLabel"),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- BOTÓN DE REPUTACIÓN ---
                    Center(
                      child: InkWell(
                        onTap: () {
                          if (_userId != 0) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserReviewsScreen(
                                  userId: _userId,
                                  userName: "Mí",
                                ),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _reviewCount > 0
                                    ? "${_averageRating.toStringAsFixed(1)}/5 ($_reviewCount Op)"
                                    : "Sin calificaciones aún",
                                style: TextStyle(
                                  color: Colors.amber[900],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: Colors.amber[900],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
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
                            _housingTypesOptions,
                            (v) => setState(() => _housingType = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdown(
                            "Tenencia",
                            _housingOwnership,
                            _ownershipOptions,
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
                      _familyOptions,
                      (v) => setState(() => _familyComposition = v!),
                    ),
                    const SizedBox(height: 16),
                    _buildDropdown(
                      "Otras Mascotas",
                      _otherPets,
                      _petsOptions,
                      (v) => setState(() => _otherPets = v!),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdown(
                            "Tiempo Libre",
                            _timeAvailability,
                            _timeOptions,
                            (v) => setState(() => _timeAvailability = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdown(
                            "Experiencia",
                            _experience,
                            _expOptions,
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
      onChanged: _isEditing ? onChanged : null,
    );
  }
}
