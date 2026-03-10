import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/auth_repository.dart';
import 'otp_screen.dart';

/// A screen for new user registration.
///
/// It can also be used to register a second role for an existing user
/// by pre-filling data like name, email, and RUN.
class RegisterScreen extends StatefulWidget {
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
    // Initialize controllers with pre-filled data if available.
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

  /// Validates a Chilean RUN (national ID) using the Modulo 11 algorithm.
  bool _isValidRut(String rut) {
    if (rut.isEmpty) return false;
    String cleanRut = rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
    if (cleanRut.length < 2) return false;
    
    String body = cleanRut.substring(0, cleanRut.length - 1);
    String dv = cleanRut.substring(cleanRut.length - 1);

    try {
      int sum = 0;
      int multiplier = 2;
      for (int i = body.length - 1; i >= 0; i--) {
        sum += int.parse(body[i]) * multiplier;
        multiplier = (multiplier == 7) ? 2 : multiplier + 1;
      }
      int remainder = sum % 11;
      String expectedDV = (remainder == 0) ? '0' : (remainder == 1) ? 'K' : (11 - remainder).toString();
      
      return dv == expectedDV;
    } catch(e) {
      return false;
    }
  }

  /// Submits the registration form data to the repository.
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
          const SnackBar(content: Text('Registration successful. Check your email.'), backgroundColor: Colors.green),
        );
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OTPScreen(email: _emailController.text)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If a role is pre-configured, lock the role selection UI.
    bool isRoleFixed = widget.initialRole != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Create Account")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // --- Role Selection ---
                if (!isRoleFixed) ...[
                  Text("What is your goal?", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(child: _buildRoleCard(label: 'Adopt', value: 'adopter', icon: Icons.pets, color: Colors.orange)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildRoleCard(label: 'I am a Rescuer', value: 'rescuer', icon: Icons.volunteer_activism, color: Colors.blue)),
                    ],
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  // Informational message for a linked registration.
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(child: Text("Activating ${_selectedRole == 'rescuer' ? 'Rescuer' : 'Adopter'} mode for your account.", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                    ]),
                  ),
                  const SizedBox(height: 24),
                ],

                // --- Form Fields ---
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  validator: (value) => value!.isEmpty ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _runController,
                  // Disable the field only if it's pre-filled and not empty.
                  enabled: widget.initialRun == null || widget.initialRun!.isEmpty,
                  decoration: const InputDecoration(labelText: 'RUN', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge), hintText: '12.345.678-9'),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9kK]')), RutFormatter()],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (!_isValidRut(value)) return 'Invalid RUN';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  enabled: widget.initialEmail == null,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => !value!.contains('@') ? 'Invalid email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
                  validator: (value) => value!.length < 6 ? 'Minimum 6 characters' : null,
                ),
                const SizedBox(height: 30),

                // --- Submit Button ---
                _isLoading
                    ? const CircularProgressIndicator()
                    : FilledButton(
                        onPressed: _submitRegister,
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE91E63), minimumSize: const Size(double.infinity, 50)),
                        child: const Text('REGISTER'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A helper widget to build the selectable role cards.
  Widget _buildRoleCard({required String label, required String value, required IconData icon, required Color color}) {
    final isSelected = _selectedRole == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          border: Border.all(color: isSelected ? color : Colors.grey[300]!, width: isSelected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 32),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: isSelected ? color : Colors.grey[700], fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

/// A [TextInputFormatter] for formatting a Chilean RUN (national ID).
class RutFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String newText = newValue.text.replaceAll(RegExp(r'[^0-9kK]'), '').toUpperCase();
    if (newText.isEmpty) return newValue.copyWith(text: '');
    if (newText.length < 2) return newValue.copyWith(text: newText);
    
    String body = newText.substring(0, newText.length - 1);
    String dv = newText.substring(newText.length - 1);
    String formattedBody = '';
    int count = 0;

    for (int i = body.length - 1; i >= 0; i--) {
      formattedBody = body[i] + formattedBody;
      count++;
      if (count == 3 && i != 0) {
        formattedBody = '.$formattedBody';
        count = 0;
      }
    }
    
    String finalRut = '$formattedBody-$dv';
    return TextEditingValue(
      text: finalRut,
      selection: TextSelection.collapsed(offset: finalRut.length),
    );
  }
}
