import '../../user/domain/user_model.dart';
import '../../chat/domain/message_model.dart';

class Report {
  final int id;
  final int reporterId;
  final int reportedId;
  final int matchId;
  final String category;
  final String description;
  final String status;
  final DateTime createdAt;

  final User? reporter;
  final User? reported;

  // Para el detalle: lista de mensajes de evidencia
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

  factory Report.fromJson(Map<String, dynamic> json) {
    // Si viene evidencia en el JSON (desde el endpoint de detalle)
    List<ChatMessage>? evidence;
    if (json['evidence'] != null) {
      evidence = (json['evidence'] as List)
          .map(
            (m) => ChatMessage.fromJson(m, 0),
          ) // 0 porque no hay "myUserId" en admin view
          .toList();
    }

    // El objeto 'report' puede venir anidado si usamos el endpoint de detalle
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

      reporter: data['reporter'] != null
          ? User.fromJson(data['reporter'])
          : null,
      reported: data['reported'] != null
          ? User.fromJson(data['reported'])
          : null,

      evidenceMessages: evidence,
    );
  }
}
