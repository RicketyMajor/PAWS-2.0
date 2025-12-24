import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart'; // <--- FALTABA ESTA IMPORTACIÓN
import '../../data/auth_repository.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // CORREGIDO: _runController estaba declarado dos veces. Dejamos solo uno.
  final _runController = TextEditingController();

  bool _isLoading = false;
  bool _isVerifying = false;
  final ImagePicker _picker = ImagePicker();

  // --- LÓGICA MODIFICADA PARA FASE 11 ---
  Future<void> _submitRegister() async {
    if (_nameController.text.isEmpty || _runController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Llamamos al registro (Esto dispara RabbitMQ -> Email)
      await context.read<AuthRepository>().register(
        email: _emailController.text,
        password: _passwordController.text,
        name: _nameController.text,
        run: _runController.text,
      );

      if (mounted) {
        // 2. Feedback visual
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registro exitoso. Revisa tu correo.'),
            backgroundColor: Colors.blue, // Azul para indicar "info/espera"
          ),
        );

        // 3. CAMBIO CLAVE FASE 11: Navegar a OTP en lugar de cerrar
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
      // 1. Abrir Galería o Cámara
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _isVerifying = true);

      // 2. Preparar el archivo
      String fileName = image.path.split('/').last;
      FormData formData = FormData.fromMap({
        "document": await MultipartFile.fromFile(
          image.path,
          filename: fileName,
        ),
      });

      // 3. Enviar al Backend (Evil PAWS)
      // Nota: 10.0.2.2 es para Emulador Android. Si usas físico, usa tu IP local.
      var response = await Dio().post(
        'http://10.0.2.2:8080/api/v1/verification/verify',
        data: formData,
      );

      // 4. Procesar Respuesta
      if (response.statusCode == 200) {
        // Aseguramos que la respuesta sea un Map y extraemos el dato
        String extractedRun = response.data['extracted_run'];

        setState(() {
          _runController.text = extractedRun;
          _isVerifying = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Identidad Verificada: RUN detectado"),
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
              const Icon(Icons.person_add, size: 64, color: Color(0xFFE91E63)),
              const SizedBox(height: 24),

              // 1. Campo Nombre
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Email
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

              // 3. Password
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

              // --- SECCIÓN DE VERIFICACIÓN (OCR) ---
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
                            ? Container(
                                width: 24,
                                height: 24,
                                child: const CircularProgressIndicator(
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
                    // Campo RUN (Autocompletable)
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
                      readOnly:
                          false, // Permitimos editar si el OCR falla un poco
                    ),
                  ],
                ),
              ),

              // -------------------------------------
              const SizedBox(height: 24),

              // Botón Registrar
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
}
