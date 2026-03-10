// The presentation layer contains the BLoCs (business logic), screens (UI), and widgets.
import 'package:flutter/material.dart';
import '../../domain/message_model.dart';

/// A widget that displays a single chat message in a bubble.
///
/// The bubble's alignment and color change based on whether the message
/// was sent by the current user (`isMe`).
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isSeen; // A new parameter to control the "Seen" indicator.

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isSeen = false, // Defaults to false.
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      // Align the bubble to the right if it's "my" message, left otherwise.
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFFE91E63) : Colors.grey[200],
              // Apply a "tailed" border radius effect.
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                bottomRight: isMe ? Radius.zero : const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(color: isMe ? Colors.white70 : Colors.black54, fontSize: 10),
                ),
              ],
            ),
          ),
          // --- "Seen" Indicator ---
          // Displayed only if the message is the most recent one, sent by me, and has been read.
          if (isSeen && isMe)
            Padding(
              padding: const EdgeInsets.only(right: 14, bottom: 4),
              child: Text(
                "Seen",
                style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  /// Formats a DateTime object into a "HH:mm" string.
  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
