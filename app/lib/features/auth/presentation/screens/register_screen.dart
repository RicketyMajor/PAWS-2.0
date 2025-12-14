import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/auth_repository.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _runController =
      TextEditingController(); // <--- NUEVO: Controlador para RUN
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitRegister() async {
    // Validación simple antes de enviar
    if (_nameController.text.isEmpty || _runController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Llamamos al método actualizado con los parámetros nombrados
      await context.read<AuthRepository>().register(
        email: _emailController.text,
        password: _passwordController.text,
        name: _nameController.text,
        run: _runController.text, // <--- Enviamos el RUN
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Cuenta creada! Inicia sesión.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        // Aquí se mostrará el error del backend de forma más limpia
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

              // 2. Campo RUN (Nuevo)
              TextField(
                controller: _runController,
                decoration: const InputDecoration(
                  labelText: 'RUN (Sin puntos ni guión)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge), // Icono de credencial
                ),
                keyboardType: TextInputType.number, // Teclado numérico
              ),
              const SizedBox(height: 16),

              // 3. Email
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

              // 4. Password
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

              // Botón
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
