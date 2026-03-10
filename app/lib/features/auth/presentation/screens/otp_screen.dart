import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../data/auth_repository.dart';
import '../../../../core/presentation/main_layout_screen.dart';

/// A screen for users to enter the One-Time Password (OTP) they received via email.
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

  /// Calls the repository to verify the entered OTP.
  /// On success, it decodes the new token to get the user's role and navigates
  /// to the main part of the app. On failure, it shows an error message.
  void _verify() async {
    setState(() => _isLoading = true);

    final token = await _authRepo.verifyOtp(widget.email, _codeController.text);

    setState(() => _isLoading = false);

    if (token != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account verified! Signing in...'), backgroundColor: Colors.green),
        );

        // Decode the token to determine the user's role.
        Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
        String role = decodedToken['role'] ?? 'adopter';

        // Navigate to the main layout, replacing the entire navigation stack.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => MainLayoutScreen(role: role)),
          (route) => false,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect or expired code'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Code")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "We've sent a code to ${widget.email}",
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
                    child: const Text("Verify Account"),
                  ),
          ],
        ),
      ),
    );
  }
}
