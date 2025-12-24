import 'package:flutter/material.dart';
import '../../data/auth_repository.dart';
// Importamos la pantalla principal (MatchScreen)
// Ajusta la ruta si tu carpeta se llama distinto, pero según tu estructura es esta:
import '../../../../features/pets/presentation/screens/match_screen.dart';

class OTPScreen extends StatefulWidget {
  final String email;

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

    // Llamada al repositorio
    final success = await _authRepo.verifyOtp(
      widget.email,
      _codeController.text,
    );

    setState(() => _isLoading = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Cuenta verificada!'),
            backgroundColor: Colors.green,
          ),
        );

        // --- CAMBIO CLAVE AQUÍ ---
        // En lugar de volver al Login, entramos directo a la App (MatchScreen)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MatchScreen()),
          (route) => false, // Esto borra todo el historial anterior
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Código incorrecto'),
            backgroundColor: Colors.red,
          ),
        );
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
