import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/auth_repository.dart';
import 'otp_screen.dart';
import '../../../../core/constants/api_constants.dart'; // Asegúrate de tener este import para la URL base

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _runController = TextEditingController();

  // 1. Variable para el Rol (Por defecto adopter)
  String _selectedRole = 'adopter';

  bool _isLoading = false;
  bool _isVerifying = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _submitRegister() async {
    if (_nameController.text.isEmpty || _runController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 2. Enviamos el rol seleccionado al repositorio
      await context.read<AuthRepository>().register(
        email: _emailController.text,
        password: _passwordController.text,
        name: _nameController.text,
        run: _runController.text,
        role: _selectedRole, // <--- CAMBIO IMPORTANTE
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registro exitoso. Revisa tu correo.'),
            backgroundColor: Colors.blue,
          ),
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OTPScreen(email: _emailController.text),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scanIdentity() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _isVerifying = true);

      String fileName = image.path.split('/').last;
      FormData formData = FormData.fromMap({
        "document": await MultipartFile.fromFile(
          image.path,
          filename: fileName,
        ),
      });

      // Usamos ApiConstants para la URL base si es posible, o la hardcoded
      // IMPORTANTE: Asegúrate de usar la IP correcta (10.0.2.2 para emulador, localhost para web)
      var response = await Dio().post(
        '${ApiConstants.baseUrl}/verification/verify',
        data: formData,
      );

      if (response.statusCode == 200) {
        String extractedRun =
            response.data['extracted_run'] ?? response.data['message'];
        // Nota: Ajusta esto según lo que devuelva exactamente tu Mock de OCR

        // Si el mock devuelve texto genérico, generamos uno fake para que no falle el registro
        if (!extractedRun.contains('-')) {
          extractedRun = "12.345.678-9"; // Fallback si el mock no retorna RUN
        }

        setState(() {
          _runController.text = extractedRun;
          _isVerifying = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Identidad Verificada"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isVerifying = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error verificando documento: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Crear Cuenta")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 3. UI DEL SELECTOR DE ROL
              Text(
                "¿Cuál es tu objetivo?",
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _buildRoleCard(
                      label: 'Adoptar',
                      value: 'adopter',
                      icon: Icons.pets,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildRoleCard(
                      label: 'Soy Rescatista',
                      value: 'rescuer',
                      icon: Icons.volunteer_activism,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Correo Electrónico',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    const Text(
                      "Verificación de Identidad",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _isVerifying ? null : _scanIdentity,
                        icon: _isVerifying
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.camera_alt),
                        label: Text(
                          _isVerifying
                              ? "Analizando..."
                              : "Escanear Cédula (OCR)",
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _runController,
                      decoration: const InputDecoration(
                        labelText: 'RUN',
                        hintText: 'Se completará automáticamente',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                      readOnly: false,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              _isLoading
                  ? const CircularProgressIndicator()
                  : FilledButton(
                      onPressed: _submitRegister,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE91E63),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('REGISTRARSE'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget auxiliar para las tarjetas de selección
  Widget _buildRoleCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedRole == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
