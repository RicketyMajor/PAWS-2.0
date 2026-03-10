// The domain layer contains the core models of the application.
import '../../user/domain/user_model.dart';
import '../../chat/domain/message_model.dart';

/// Represents a user-filed report, used in the admin dashboard.
class Report {
  final int id;
  final int reporterId;
  final int reportedId;
  final int matchId;
  final String category;
  final String description;
  final String status;
  final DateTime createdAt;

  // Associated user data, preloaded from the API.
  final User? reporter;
  final User? reported;

  // For the report detail view, includes the chat history as evidence.
  final List<ChatMessage>? evidenceMessages;

  Report({
    required this.id,
    required this.reporterId,
    required this.reportedId,
    required this.matchId,
    required this.category,
    required this.description,
    required this.status,
    required this.createdAt,
    this.reporter,
    this.reported,
    this.evidenceMessages,
  });

  /// Creates a [Report] from a JSON map.
  /// This factory can handle both the list view and the detail view, which may have nested data.
  factory Report.fromJson(Map<String, dynamic> json) {
    // If 'evidence' is present in the JSON (from the detail endpoint), parse it.
    List<ChatMessage>? evidence;
    if (json['evidence'] != null) {
      evidence = (json['evidence'] as List)
          .map((m) => ChatMessage.fromJson(m, 0)) // 0 for myUserId as it's an admin view.
          .toList();
    }

    // The main report data might be nested under a 'report' key in the detail view.
    final data = json['report'] ?? json;

    return Report(
      id: data['ID'] ?? data['id'] ?? 0,
      reporterId: data['reporter_id'] ?? 0,
      reportedId: data['reported_id'] ?? 0,
      matchId: data['match_id'] ?? 0,
      category: data['category'] ?? 'other',
      description: data['description'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: DateTime.parse(data['CreatedAt'] ?? data['created_at']),
      reporter: data['reporter'] != null ? User.fromJson(data['reporter']) : null,
      reported: data['reported'] != null ? User.fromJson(data['reported']) : null,
      evidenceMessages: evidence,
    );
  }
}
