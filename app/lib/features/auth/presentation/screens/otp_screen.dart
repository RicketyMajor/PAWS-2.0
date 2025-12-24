import 'package:flutter/material.dart';
import '../../data/auth_repository.dart'; // Importa tu repo

class OTPScreen extends StatefulWidget {
  final String email; // Necesitamos el email para verificar

  const OTPScreen({Key? key, required this.email}) : super(key: key);

  @override
  _OTPScreenState createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final TextEditingController _codeController = TextEditingController();
  final AuthRepository _authRepo = AuthRepository();
  bool _isLoading = false;

  void _verify() async {
    setState(() => _isLoading = true);
    final success = await _authRepo.verifyOtp(
      widget.email,
      _codeController.text,
    );
    setState(() => _isLoading = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Cuenta verificada! Inicia sesión.'),
            backgroundColor: Colors.green,
          ),
        );
        // Esto hace "pop" de todo hasta volver a la primera pantalla (Login)
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Código incorrecto')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verificar Código")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Hemos enviado un código a ${widget.email}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                hintText: "000000",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _verify,
                    child: const Text("Verificar Cuenta"),
                  ),
          ],
        ),
      ),
    );
  }
}
