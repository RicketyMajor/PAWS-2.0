import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/auth_repository.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  // Parámetros opcionales para pre-llenar datos al cambiar de rol
  final String? initialName;
  final String? initialEmail;
  final String? initialRun;
  final String? initialRole;

  const RegisterScreen({
    super.key,
    this.initialName,
    this.initialEmail,
    this.initialRun,
    this.initialRole,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final _passwordController = TextEditingController();
  late TextEditingController _runController;

  late String _selectedRole;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Inicializamos con los datos pre-cargados si existen
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    _runController = TextEditingController(text: widget.initialRun ?? '');
    _selectedRole = widget.initialRole ?? 'adopter';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _runController.dispose();
    super.dispose();
  }

  // Algoritmo de validación de RUT
  bool _isValidRut(String rut) {
    if (rut.isEmpty) return false;
    String cleanRut = rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
    if (cleanRut.length < 2) return false;
    String body = cleanRut.substring(0, cleanRut.length - 1);
    String dv = cleanRut.substring(cleanRut.length - 1);
    int suma = 0;
    int multiplicador = 2;
    for (int i = body.length - 1; i >= 0; i--) {
      suma += int.parse(body[i]) * multiplicador;
      multiplicador++;
      if (multiplicador == 8) multiplicador = 2;
    }
    int resto = suma % 11;
    String dvEsperado = (resto == 0)
        ? '0'
        : (resto == 1)
        ? 'K'
        : (11 - resto).toString();
    return dv == dvEsperado;
  }

  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await context.read<AuthRepository>().register(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        run: _runController.text.trim(),
        role: _selectedRole,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registro exitoso. Revisa tu correo.'),
            backgroundColor: Colors.green,
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

  @override
  Widget build(BuildContext context) {
    // Si viene pre-configurado para un rol, bloqueamos la selección para evitar errores
    bool isRoleFixed = widget.initialRole != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Crear Cuenta")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                if (!isRoleFixed) ...[
                  Text(
                    "¿Cuál es tu objetivo?",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                ] else ...[
                  // Mensaje informativo si es un registro vinculado
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Activando modo ${_selectedRole == 'rescuer' ? 'Rescatista' : 'Adoptante'} para tu cuenta.",
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) =>
                      value!.isEmpty ? 'Ingresa tu nombre' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _runController,
                  // Bloquear SOLO si viene pre-llenado y NO está vacío
                  enabled:
                      widget.initialRun == null || widget.initialRun!.isEmpty,
                  decoration: const InputDecoration(
                    labelText: 'RUN',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                    hintText: '12.345.678-9',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9kK]')),
                    RutFormatter(),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Requerido';
                    if (!_isValidRut(value)) return 'RUN inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _emailController,
                  enabled:
                      widget.initialEmail ==
                      null, // Bloquear si viene pre-llenado
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                      !value!.contains('@') ? 'Correo inválido' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) =>
                      value!.length < 6 ? 'Mínimo 6 caracteres' : null,
                ),
                const SizedBox(height: 30),

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
      ),
    );
  }

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

class RutFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String newText = newValue.text
        .replaceAll(RegExp(r'[^0-9kK]'), '')
        .toUpperCase();
    if (newText.isEmpty) return newValue.copyWith(text: '');
    if (newText.length < 2) return newValue.copyWith(text: newText);
    String cuerpo = newText.substring(0, newText.length - 1);
    String dv = newText.substring(newText.length - 1);
    String cuerpoFormateado = '';
    int contador = 0;
    for (int i = cuerpo.length - 1; i >= 0; i--) {
      cuerpoFormateado = cuerpo[i] + cuerpoFormateado;
      contador++;
      if (contador == 3 && i != 0) {
        cuerpoFormateado = '.$cuerpoFormateado';
        contador = 0;
      }
    }
    String rutFinal = '$cuerpoFormateado-$dv';
    return TextEditingValue(
      text: rutFinal,
      selection: TextSelection.collapsed(offset: rutFinal.length),
    );
  }
}
