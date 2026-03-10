import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/admin_repository.dart';
import '../../domain/report_model.dart';
import '../../../chat/presentation/widgets/chat_bubble.dart'; // Re-using ChatBubble
import '../../../../core/utils/image_helper.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/screens/login_screen.dart';

// =========================================================================
// Admin Dashboard Screen (Main List)
// =========================================================================

/// The main dashboard for administrators, displaying a list of pending reports.
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

  /// Fetches the list of pending reports from the repository.
  void _loadReports() {
    setState(() {
      _reportsFuture = context.read<AdminRepository>().getReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Resolution Center ⚖️"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: "Log Out",
            onPressed: () async {
              await context.read<AuthRepository>().logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
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
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_outline, size: 60, color: Colors.green),
                SizedBox(height: 16),
                Text("All clear! No pending reports."),
              ]),
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
                  leading: CircleAvatar(backgroundColor: Colors.red[50], child: const Icon(Icons.warning_amber_rounded, color: Colors.red)),
                  title: Text(_translateCategory(report.category), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Reported: ${report.reported?.name ?? 'User'} \nBy: ${report.reporter?.name ?? 'User'}"),
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

  /// Navigates to the detail screen for a specific report.
  void _openReportDetail(BuildContext context, int reportId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(reportId: reportId, onResolved: _loadReports),
      ),
    );
  }

  /// Translates report categories from English keys to Spanish for display.
  String _translateCategory(String cat) {
    switch (cat) {
      case 'abuse': return 'Animal Abuse';
      case 'scam': return 'Scam / Fraud';
      case 'hate': return 'Hate Speech';
      case 'spam': return 'Spam';
      default: return 'Other';
    }
  }
}


// =========================================================================
// Report Detail Screen
// =========================================================================

/// Displays the details of a single report, including chat evidence and resolution actions.
class ReportDetailScreen extends StatefulWidget {
  final int reportId;
  final VoidCallback onResolved; // Callback to refresh the dashboard list.

  const ReportDetailScreen({super.key, required this.reportId, required this.onResolved});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late Future<Report> _detailFuture;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<AdminRepository>().getReportDetails(widget.reportId);
  }

  /// Resolves a report by taking an action ('ban' or 'dismiss').
  Future<void> _resolve(int id, String action, bool blacklist) async {
    setState(() => _isProcessing = true);
    try {
      await context.read<AdminRepository>().resolveReport(id, action, blacklist);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'ban' ? "User banned successfully" : "Report dismissed")),
      );
      widget.onResolved(); // Refresh the dashboard list.
      Navigator.pop(context); // Go back to the dashboard.
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Case Review")),
      body: FutureBuilder<Report>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final report = snapshot.data!;
          return Column(
            children: [
              // --- 1. Report Info Header ---
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow("Reporter:", report.reporter?.name, report.reporter?.email),
                    const Divider(),
                    _buildInfoRow("Accused:", report.reported?.name, report.reported?.email, isDestructive: true),
                    const SizedBox(height: 10),
                    Text("Reason: ${_translateCategory(report.category)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("Description: \"${report.description}\"", style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              const Divider(height: 1),

              // --- 2. Evidence Viewer (Chat History) ---
              Expanded(
                child: Container(
                  color: Colors.grey[100],
                  child: report.evidenceMessages == null || report.evidenceMessages!.isEmpty
                      ? const Center(child: Text("No chat history available."))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: report.evidenceMessages!.length,
                          itemBuilder: (context, index) {
                            final msg = report.evidenceMessages![index];
                            // If the message is from the reporter, align it right (as if it's "me").
                            final isReporter = msg.senderId == report.reporterId;
                            return ChatBubble(message: msg, isMe: isReporter);
                          },
                        ),
                ),
              ),

              // --- 3. Action Buttons ---
              if (!_isProcessing)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => _resolve(report.id, 'dismiss', false), child: const Text("Dismiss"))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () => _showBanDialog(report.id),
                        child: const Text("BAN USER"),
                      ),
                    ),
                  ]),
                )
              else
                const Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()),
            ],
          );
        },
      ),
    );
  }

  /// Displays a confirmation dialog before banning a user.
  void _showBanDialog(int reportId) {
    bool addToBlacklist = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Confirm Ban"),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("The user will immediately lose access to their account."),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text("Add to Public Blacklist"),
                  subtitle: const Text("Their name and RUN will be visible in security searches."),
                  value: addToBlacklist,
                  activeColor: Colors.red,
                  onChanged: (val) => setState(() => addToBlacklist = val!),
                ),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resolve(reportId, 'ban', addToBlacklist);
                  },
                  child: const Text("EXECUTE BAN", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String? name, String? email, {bool isDestructive = false}) {
    return Row(children: [
      Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isDestructive ? Colors.red : Colors.black)),
      const SizedBox(width: 8),
      Expanded(child: Text("$name ($email)", overflow: TextOverflow.ellipsis)),
    ]);
  }
}
