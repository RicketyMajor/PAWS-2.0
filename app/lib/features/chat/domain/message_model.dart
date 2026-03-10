// The domain layer contains the core models of the application.

/// Represents a single chat message.
class ChatMessage {
  final int id;
  final int matchId;
  final int senderId;
  final String content;
  final bool isRead;
  final DateTime createdAt;

  /// A UI helper field to determine if the message was sent by the current user.
  /// This is calculated at runtime and not stored in the database.
  final bool isMe;

  ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.content,
    required this.isRead,
    required this.createdAt,
    this.isMe = false,
  });

  /// Creates a [ChatMessage] from a JSON map, calculating the [isMe] field.
  factory ChatMessage.fromJson(Map<String, dynamic> json, int myUserId) {
    return ChatMessage(
      id: json['id'] ?? 0,
      matchId: json['match_id'] ?? 0,
      senderId: json['sender_id'] ?? 0,
      content: json['content'] ?? '',
      isRead: json['is_read'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      isMe: (json['sender_id'] ?? 0) == myUserId,
    );
  }
}
