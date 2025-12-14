class ChatMessage {
  final String text;
  final bool isMe; // True si lo escribí yo, False si llegó del servidor
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isMe,
    required this.timestamp,
  });
}
