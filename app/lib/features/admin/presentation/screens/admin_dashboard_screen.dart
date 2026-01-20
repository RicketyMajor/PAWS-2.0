import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/admin_repository.dart';
import '../../domain/report_model.dart';
import '../../../chat/presentation/widgets/chat_bubble.dart'; // Reutilizamos Bubble
import '../../../../core/utils/image_helper.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<List<Report>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  void _loadReports() {
    setState(() {
      _reportsFuture = context.read<AdminRepository>().getReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Centro de Resolución ⚖️"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      backgroundColor: Colors.grey[100],
      body: FutureBuilder<List<Report>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final reports = snapshot.data ?? [];

          if (reports.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 60,
                    color: Colors.green,
                  ),
                  SizedBox(height: 16),
                  Text("¡Todo limpio! No hay reportes pendientes."),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red[50],
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                    ),
                  ),
                  title: Text(
                    _translateCategory(report.category),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "Reportado: ${report.reported?.name ?? 'Usuario'} \nPor: ${report.reporter?.name ?? 'Usuario'}",
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  isThreeLine: true,
                  onTap: () => _openReportDetail(context, report.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _translateCategory(String cat) {
    switch (cat) {
      case 'abuse':
        return 'Maltrato Animal';
      case 'scam':
        return 'Estafa / Fraude';
      case 'hate':
        return 'Lenguaje Ofensivo';
      case 'spam':
        return 'Spam';
      default:
        return 'Otro Motivo';
    }
  }

  void _openReportDetail(BuildContext context, int reportId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReportDetailScreen(reportId: reportId, onResolved: _loadReports),
      ),
    );
  }
}

// --- PANTALLA DE DETALLE (SUB-CLASE PARA MANTENER TODO JUNTO) ---

class ReportDetailScreen extends StatefulWidget {
  final int reportId;
  final VoidCallback onResolved;

  const ReportDetailScreen({
    super.key,
    required this.reportId,
    required this.onResolved,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late Future<Report> _detailFuture;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<AdminRepository>().getReportDetails(
      widget.reportId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Revisión de Caso")),
      body: FutureBuilder<Report>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final report = snapshot.data!;
          return Column(
            children: [
              // 1. INFO HEADER (Datos Duros)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                      "Denunciante:",
                      report.reporter?.name,
                      report.reporter?.email,
                    ),
                    const Divider(),
                    _buildInfoRow(
                      "ACUSADO:",
                      report.reported?.name,
                      report.reported?.email,
                      isDestructive: true,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Motivo: ${_translateCategory(report.category)}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Descripción: \"${report.description}\"",
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 2. VISOR DE EVIDENCIA (Chat)
              Expanded(
                child: Container(
                  color: Colors.grey[100],
                  child:
                      report.evidenceMessages == null ||
                          report.evidenceMessages!.isEmpty
                      ? const Center(
                          child: Text("No hay historial de chat disponible."),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: report.evidenceMessages!.length,
                          itemBuilder: (context, index) {
                            final msg = report.evidenceMessages![index];
                            // Lógica de visualización:
                            // Si el mensaje es del REPORTER, lo ponemos a la DERECHA (como si fuera "yo" enviando la prueba)
                            // Si es del ACUSADO, a la IZQUIERDA.
                            final isReporter =
                                msg.senderId == report.reporterId;

                            return ChatBubble(message: msg, isMe: isReporter);
                          },
                        ),
                ),
              ),

              // 3. BOTONES DE ACCIÓN
              if (!_isProcessing)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              _resolve(report.id, 'dismiss', false),
                          child: const Text("Desestimar"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _showBanDialog(report.id),
                          child: const Text("SANCIONAR"),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String? name,
    String? email, {
    bool isDestructive = false,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDestructive ? Colors.red : Colors.black,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text("$name ($email)", overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  String _translateCategory(String cat) {
    switch (cat) {
      case 'abuse':
        return 'Maltrato Animal';
      case 'scam':
        return 'Estafa / Fraude';
      case 'hate':
        return 'Lenguaje Ofensivo';
      case 'spam':
        return 'Spam';
      default:
        return 'Otro Motivo';
    }
  }

  void _showBanDialog(int reportId) {
    bool addToBlacklist = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Confirmar Sanción"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "El usuario perderá acceso a su cuenta inmediatamente.",
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text("Agregar a Blacklist Pública"),
                    subtitle: const Text(
                      "Su nombre y RUT serán visibles en búsquedas de seguridad.",
                    ),
                    value: addToBlacklist,
                    activeColor: Colors.red,
                    onChanged: (val) => setState(() => addToBlacklist = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resolve(reportId, 'ban', addToBlacklist);
                  },
                  child: const Text(
                    "EJECUTAR BAN",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _resolve(int id, String action, bool blacklist) async {
    setState(() => _isProcessing = true);
    try {
      await context.read<AdminRepository>().resolveReport(
        id,
        action,
        blacklist,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'ban'
                ? "Usuario baneado correctamente"
                : "Reporte desestimado",
          ),
        ),
      );
      widget.onResolved(); // Recargar lista
      Navigator.pop(context); // Volver al dashboard
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }
}
