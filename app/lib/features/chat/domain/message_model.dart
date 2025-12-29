class ChatMessage {
  final int id;
  final int matchId;
  final int senderId;
  final String content;
  final bool isRead;
  final DateTime createdAt;

  // UI Helper: Para saber si el mensaje es mío o del otro
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
