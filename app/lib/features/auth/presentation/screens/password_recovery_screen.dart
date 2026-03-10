import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/auth_repository.dart';

/// A multi-step screen that guides the user through the password recovery process.
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final PageController _pageController = PageController();
  final AuthRepository _authRepo = AuthRepository();

  // --- State for the multi-step form ---
  String _email = '';
  String _code = '';
  String _newPassword = '';
  bool _isLoading = false;
  int _currentStep = 0; // 0: Email, 1: Code, 2: New Password

  // --- Text Field Controllers ---
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  /// Helper to show a SnackBar message.
  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  // --- Step 1: Request OTP ---
  Future<void> _requestOtp() async {
    if (_emailCtrl.text.isEmpty || !_emailCtrl.text.contains('@')) {
      _showMessage("Please enter a valid email", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authRepo.forgotPassword(_emailCtrl.text.trim());
      setState(() {
        _email = _emailCtrl.text.trim();
        _currentStep = 1;
      });
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      _showMessage("Code sent to $_email");
    } catch (e) {
      _showMessage(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Step 2: Verify Code ---
  Future<void> _verifyCode() async {
    if (_codeCtrl.text.length != 6) {
      _showMessage("The code must be 6 digits", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final isValid = await _authRepo.verifyRecoveryCode(_email, _codeCtrl.text.trim());
      if (isValid) {
        setState(() {
          _code = _codeCtrl.text.trim();
          _currentStep = 2;
        });
        _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      } else {
        _showMessage("Incorrect code", isError: true);
      }
    } catch (e) {
      _showMessage("Error verifying code", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Step 3: Reset Password ---
  Future<void> _resetPassword() async {
    if (_passCtrl.text.length < 6) {
      _showMessage("Password must be at least 6 characters", isError: true);
      return;
    }
    if (_passCtrl.text != _passConfirmCtrl.text) {
      _showMessage("Passwords do not match", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authRepo.resetPassword(_email, _passCtrl.text);
      _showMessage("Password reset successfully! Please log in.");
      if (mounted) Navigator.pop(context); // Go back to the login screen.
    } catch (e) {
      _showMessage(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Recover Account")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // --- Step Progress Indicator ---
            Row(
              children: [
                _buildStep(0, "Email"),
                _buildLine(0),
                _buildStep(1, "Code"),
                _buildLine(1),
                _buildStep(2, "New Key"),
              ],
            ),
            const SizedBox(height: 30),

            // --- PageView for the steps ---
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disable manual swiping.
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
    );
  }

  // =========================================================================
  // UI Helper Widgets
  // =========================================================================

  Widget _buildStep(int step, String label) {
    bool isActive = _currentStep >= step;
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: isActive ? const Color(0xFFE91E63) : Colors.grey[300],
          child: Text("${step + 1}", style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: isActive ? Colors.black : Colors.grey)),
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
        const Text("Enter your email to receive a recovery code", textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const CircularProgressIndicator()
            : FilledButton(onPressed: _requestOtp, child: const Text("SEND CODE")),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("We've sent a code to $_email", textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(labelText: "6-digit code", border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const CircularProgressIndicator()
            : FilledButton(onPressed: _verifyCode, child: const Text("VERIFY")),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Create a new, secure password", textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: "New Password", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passConfirmCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: "Confirm Password", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock_outline)),
        ),
        const SizedBox(height: 20),
        _isLoading
            ? const CircularProgressIndicator()
            : FilledButton(onPressed: _resetPassword, child: const Text("CHANGE PASSWORD")),
      ],
    );
  }
}
