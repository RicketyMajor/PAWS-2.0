import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/security_repository.dart';

class BlacklistSearchScreen extends StatefulWidget {
  const BlacklistSearchScreen({super.key});

  @override
  State<BlacklistSearchScreen> createState() => _BlacklistSearchScreenState();
}

class _BlacklistSearchScreenState extends State<BlacklistSearchScreen> {
  final _rutController = TextEditingController();
  final _formKey = GlobalKey<FormState>(); // Para validación visual

  bool _isLoading = false;
  Map<String, dynamic>? _result;
  bool _hasSearched = false;

  Future<void> _search() async {
    // 1. Ocultar teclado
    FocusScope.of(context).unfocus();

    // 2. Validar formato y existencia matemática del RUT
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _result = null;
      _hasSearched = false;
    });

    try {
      final repo = context.read<SecurityRepository>();

      // Enviamos el RUT tal cual está en el input (el backend debe limpiarlo o recibirlo así)
      final data = await repo.checkBlacklist(_rutController.text.trim());

      if (!mounted) return;
      setState(() {
        _result = data;
        _hasSearched = true;
      });
    } catch (e) {
      if (!mounted) return;
      // The repository already phrases these for the user.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Consulta de Seguridad"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          // Envolvemos en Form para activar validadores
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 60,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 16),
              const Text(
                "Verifica antes de confiar",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Ingresa el RUT de la persona para consultar si tiene antecedentes en nuestra comunidad.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // --- INPUT DE RUT MEJORADO ---
              TextFormField(
                controller: _rutController,
                keyboardType:
                    TextInputType.text, // Teclado completo para la 'K'
                textInputAction: TextInputAction.search,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(
                    12,
                  ), // 12.345.678-9 (12 chars)
                  RutFormatter(), // <--- Formateo automático
                ],
                decoration: const InputDecoration(
                  labelText: "RUT (Ej: 12.345.678-9)",
                  hintText: "Ingrese RUT",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                // Validación en tiempo real (o al enviar)
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return "El RUT es obligatorio";
                  if (!RutValidator.isValid(value))
                    return "RUT inválido (Revise dígito verificador)";
                  return null;
                },
                onFieldSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 16),

              // BOTÓN BUSCAR (Para mayor claridad)
              FilledButton.icon(
                onPressed: _isLoading ? null : _search,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _isLoading ? "Verificando..." : "Consultar Antecedentes",
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE91E63),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),

              const SizedBox(height: 24),

              // RESULTADOS
              if (_hasSearched && _result != null) _buildResultCard(_result!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> data) {
    final bool found = data['found'] == true;

    if (found) {
      return Card(
        color: Colors.red[50],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.red, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 8),
              const Text(
                "¡ALERTA DE ANTECEDENTES!",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Nombre: ${data['name']}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(
                  "Motivo: ${data['reason']}",
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Te recomendamos NO realizar adopciones con esta persona.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Card(
        color: Colors.green[50],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.green, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 48,
              ),
              const SizedBox(height: 8),
              const Text(
                "Sin Antecedentes en PAWS",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Este RUT no figura en nuestra lista de seguridad actual.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.green),
              ),
            ],
          ),
        ),
      );
    }
  }
}

// =============================================================================
// UTILIDADES RUT (Formato y Validación Chile)
// =============================================================================

/// Formateador automático: Transforma "123456789" -> "12.345.678-9"
class RutFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. Limpiar caracteres no válidos (solo números y k)
    String raw = newValue.text
        .replaceAll(RegExp(r'[^0-9kK]'), '')
        .toUpperCase();

    if (raw.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // 2. Separar cuerpo y dígito verificador
    String cuerpo = '';
    String dv = '';

    if (raw.length > 1) {
      cuerpo = raw.substring(0, raw.length - 1);
      dv = raw.substring(raw.length - 1);
    } else {
      cuerpo = raw;
    }

    // 3. Formatear cuerpo con puntos
    // Recorremos de atrás hacia adelante insertando puntos cada 3 dígitos
    String cuerpoFormateado = '';
    int contador = 0;
    for (int i = cuerpo.length - 1; i >= 0; i--) {
      cuerpoFormateado = cuerpo[i] + cuerpoFormateado;
      contador++;
      if (contador == 3 && i > 0) {
        cuerpoFormateado = '.$cuerpoFormateado';
        contador = 0;
      }
    }

    // 4. Unir con guión
    String newText = cuerpoFormateado + (dv.isNotEmpty ? '-$dv' : '');

    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

/// Validador Matemático (Módulo 11)
class RutValidator {
  static bool isValid(String rut) {
    if (rut.isEmpty) return false;

    // Limpiar puntos y guión para obtener el RAW
    String cleanRut = rut.replaceAll(RegExp(r'[\.\-]'), '').toUpperCase();

    // Validar largo mínimo (al menos 1 número + DV = 2 chars)
    if (cleanRut.length < 2) return false;

    // Separar cuerpo y DV
    String body = cleanRut.substring(0, cleanRut.length - 1);
    String dv = cleanRut.substring(cleanRut.length - 1);

    // Validar que el cuerpo sea numérico
    if (!RegExp(r'^[0-9]+$').hasMatch(body)) return false;

    // Calcular DV esperado (Algoritmo Módulo 11)
    int sum = 0;
    int multiplier = 2;

    // Recorrer el cuerpo de derecha a izquierda multiplicando por la serie 2,3,4,5,6,7
    for (int i = body.length - 1; i >= 0; i--) {
      sum += int.parse(body[i]) * multiplier;
      multiplier++;
      if (multiplier > 7) multiplier = 2;
    }

    int mod = 11 - (sum % 11);
    String expectedDv;

    if (mod == 11) {
      expectedDv = '0';
    } else if (mod == 10) {
      expectedDv = 'K';
    } else {
      expectedDv = mod.toString();
    }

    return dv == expectedDv;
  }
}
