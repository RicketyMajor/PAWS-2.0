import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/auth_repository.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final PageController _pageController = PageController();
  final _authRepo =
      AuthRepository(); // Instancia directa o vía context si prefieres

  // Estado del formulario
  String _email = '';
  String _code = '';
  String _newPassword = '';

  bool _isLoading = false;
  int _currentStep = 0; // 0: Email, 1: Código, 2: Nueva Password

  // Controladores
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // PASO 1: Enviar correo
  Future<void> _requestOtp() async {
    if (_emailCtrl.text.isEmpty || !_emailCtrl.text.contains('@')) {
      _showMessage("Ingresa un correo válido", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authRepo.forgotPassword(_emailCtrl.text.trim());
      setState(() {
        _email = _emailCtrl.text.trim();
        _currentStep = 1;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _showMessage("Código enviado a $_email");
    } catch (e) {
      _showMessage(e.toString(), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // PASO 2: Verificar código
  Future<void> _verifyCode() async {
    if (_codeCtrl.text.length != 6) {
      _showMessage("El código debe tener 6 dígitos", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final isValid = await _authRepo.verifyRecoveryCode(
        _email,
        _codeCtrl.text.trim(),
      );
      if (isValid) {
        setState(() {
          _code = _codeCtrl.text.trim();
          _currentStep = 2;
        });
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _showMessage("Código incorrecto", isError: true);
      }
    } catch (e) {
      _showMessage("Error verificando código", isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // PASO 3: Cambiar contraseña
  Future<void> _resetPassword() async {
    if (_passCtrl.text.length < 6) {
      _showMessage(
        "La contraseña debe tener al menos 6 caracteres",
        isError: true,
      );
      return;
    }
    if (_passCtrl.text != _passConfirmCtrl.text) {
      _showMessage("Las contraseñas no coinciden", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authRepo.resetPassword(_email, _passCtrl.text);
      _showMessage("¡Contraseña restablecida! Inicia sesión.");
      if (mounted) Navigator.pop(context); // Volver al login
    } catch (e) {
      _showMessage(e.toString(), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Recuperar Cuenta")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                // Indicador de pasos
                Row(
                  children: [
                    _buildStep(0, "Correo"),
                    _buildLine(0),
                    _buildStep(1, "Código"),
                    _buildLine(1),
                    _buildStep(2, "Nueva Clave"),
                  ],
                ),
                const SizedBox(height: 30),

                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics:
                        const NeverScrollableScrollPhysics(), // Bloquear swipe manual
                    children: [
                      _buildEmailStep(),
                      _buildCodeStep(),
                      _buildPasswordStep(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Widgets de UI
  Widget _buildStep(int step, String label) {
    bool isActive = _currentStep >= step;
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: isActive
              ? const Color(0xFFE91E63)
              : Colors.grey[300],
          child: Text(
            "${step + 1}",
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? Colors.black : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildLine(int step) {
    return Expanded(
      child: Container(
        height: 2,
        color: _currentStep > step ? const Color(0xFFE91E63) : Colors.grey[300],
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Ingresa tu correo para recibir el código",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: "Correo Electrónico",
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email),
          ),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const CircularProgressIndicator()
            : FilledButton(
                onPressed: _requestOtp,
                child: const Text("ENVIAR CÓDIGO"),
              ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Hemos enviado un código a $_email", textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(
            labelText: "Código de 6 dígitos",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const CircularProgressIndicator()
            : FilledButton(
                onPressed: _verifyCode,
                child: const Text("VERIFICAR"),
              ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Crea una nueva contraseña segura",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: "Nueva Contraseña",
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passConfirmCtrl,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: "Confirmar Contraseña",
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const CircularProgressIndicator()
            : FilledButton(
                onPressed: _resetPassword,
                child: const Text("CAMBIAR CONTRASEÑA"),
              ),
      ],
    );
  }
}
