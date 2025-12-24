class ChatMessage {
  final int id;
  final int matchId;
  final int senderId;
  final String content;
  final bool isRead;
  final DateTime createdAt;

  // Auxiliar para la UI (saber si el mensaje es mío o del otro)
  // Lo calcularemos comparando senderId con mi ID de usuario
  final bool isMe;

  ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.content,
    required this.isRead,
    required this.createdAt,
    this.isMe = false, // Se asigna luego
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, int currentUserId) {
    return ChatMessage(
      id: json['id'],
      matchId: json['match_id'],
      senderId: json['sender_id'],
      content: json['content'],
      isRead: json['is_read'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      isMe: json['sender_id'] == currentUserId,
    );
  }
}
