import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/security_repository.dart';

/// A publicly accessible screen to check if a Chilean RUN (national ID)
/// is on the platform's blacklist.
class BlacklistSearchScreen extends StatefulWidget {
  const BlacklistSearchScreen({super.key});

  @override
  State<BlacklistSearchScreen> createState() => _BlacklistSearchScreenState();
}

class _BlacklistSearchScreenState extends State<BlacklistSearchScreen> {
  final _rutController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // --- UI State ---
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  bool _hasSearched = false;

  /// Performs the search by calling the repository.
  Future<void> _search() async {
    FocusScope.of(context).unfocus(); // Hide keyboard.
    if (!_formKey.currentState!.validate()) return; // Check for valid RUN format.

    setState(() {
      _isLoading = true;
      _result = null;
      _hasSearched = false;
    });

    try {
      final repo = context.read<SecurityRepository>();
      final data = await repo.checkBlacklist(_rutController.text.trim());
      setState(() {
        _result = data;
        _hasSearched = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Security Check"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Header ---
              const Icon(Icons.shield_outlined, size: 60, color: Colors.blueGrey),
              const SizedBox(height: 16),
              const Text("Verify Before You Trust", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("Enter a person's RUN to check for any records within our community.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),

              // --- RUN Input Field ---
              TextFormField(
                controller: _rutController,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.search,
                inputFormatters: [LengthLimitingTextInputFormatter(12), RutFormatter()],
                decoration: const InputDecoration(labelText: "RUN (e.g., 12.345.678-9)", hintText: "Enter RUN", border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge_outlined)),
                validator: (value) {
                  if (value == null || value.isEmpty) return "RUN is required";
                  if (!RutValidator.isValid(value)) return "Invalid RUN (Check verifier digit)";
                  return null;
                },
                onFieldSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 16),

              // --- Search Button ---
              FilledButton.icon(
                onPressed: _isLoading ? null : _search,
                icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.search),
                label: Text(_isLoading ? "Verifying..." : "Check Records"),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE91E63), padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 24),

              // --- Results Display ---
              if (_hasSearched && _result != null) _buildResultCard(_result!),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a card to display the result of the blacklist search.
  Widget _buildResultCard(Map<String, dynamic> data) {
    final bool found = data['found'] == true;

    if (found) {
      // --- Negative Result Card ---
      return Card(
        color: Colors.red[50],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.red, width: 2)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
              const SizedBox(height: 8),
              const Text("BLACKLIST ALERT!", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Text("Name: ${data['name']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withOpacity(0.3))),
                child: Text("Reason: ${data['reason']}", style: const TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 12),
              const Text("We strongly recommend NOT proceeding with adoptions with this individual.", textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic, color: Colors.redAccent)),
            ],
          ),
        ),
      );
    } else {
      // --- Positive Result Card ---
      return Card(
        color: Colors.green[50],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.green, width: 2)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
              const SizedBox(height: 8),
              const Text("No Records Found in PAWS", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              const Text("This RUN is not on our current security list.", textAlign: TextAlign.center, style: TextStyle(color: Colors.green)),
            ],
          ),
        ),
      );
    }
  }
}


// =============================================================================
//  Chilean RUN (National ID) Utilities
// =============================================================================

/// A [TextInputFormatter] that automatically formats text into the Chilean RUN format.
/// e.g., "123456789" -> "12.345.678-9"
class RutFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String raw = newValue.text.replaceAll(RegExp(r'[^0-9kK]'), '').toUpperCase();
    if (raw.isEmpty) return newValue.copyWith(text: '');

    String body = (raw.length > 1) ? raw.substring(0, raw.length - 1) : raw;
    String dv = (raw.length > 1) ? raw.substring(raw.length - 1) : '';

    String formattedBody = '';
    int count = 0;
    for (int i = body.length - 1; i >= 0; i--) {
      formattedBody = body[i] + formattedBody;
      count++;
      if (count == 3 && i > 0) {
        formattedBody = '.$formattedBody';
        count = 0;
      }
    }
    String newText = formattedBody + (dv.isNotEmpty ? '-$dv' : '');
    return newValue.copyWith(text: newText, selection: TextSelection.collapsed(offset: newText.length));
  }
}

/// A validator class for the Chilean RUN using the Modulo 11 algorithm.
class RutValidator {
  static bool isValid(String rut) {
    if (rut.isEmpty) return false;
    String cleanRut = rut.replaceAll(RegExp(r'[\.\-]'), '').toUpperCase();
    if (cleanRut.length < 2) return false;

    String body = cleanRut.substring(0, cleanRut.length - 1);
    String dv = cleanRut.substring(cleanRut.length - 1);

    if (!RegExp(r'^[0-9]+$').hasMatch(body)) return false;

    int sum = 0;
    int multiplier = 2;
    for (int i = body.length - 1; i >= 0; i--) {
      sum += int.parse(body[i]) * multiplier;
      multiplier = (multiplier == 7) ? 2 : multiplier + 1;
    }

    int mod = 11 - (sum % 11);
    String expectedDv;

    if (mod == 11) expectedDv = '0';
    else if (mod == 10) expectedDv = 'K';
    else expectedDv = mod.toString();

    return dv == expectedDv;
  }
}
