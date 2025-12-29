import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/chat_bloc.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';

class ChatScreen extends StatelessWidget {
  final int matchId;
  final String peerName; // Nombre de la otra persona

  const ChatScreen({super.key, required this.matchId, required this.peerName});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ChatBloc(repository: RepositoryProvider.of<ChatRepository>(context))
            ..add(InitChat(matchId)),
      child: Scaffold(
        backgroundColor: const Color(0xFFECE5DD), // Fondo tipo WhatsApp
        appBar: AppBar(
          title: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  peerName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFE91E63), // Color PAWS
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            // LISTA DE MENSAJES
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state is ChatLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is ChatLoaded) {
                    if (state.messages.isEmpty) {
                      return _buildEmptyState();
                    }

                    // TRUCO DE CHAT PRO:
                    // Usamos la lista invertida (reverse: true).
                    // Esto hace que el scroll empiece desde abajo y maneja mejor el teclado.
                    final reversedMessages = state.messages.reversed.toList();

                    return ListView.builder(
                      reverse: true, // <--- LA CLAVE
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 20,
                      ),
                      itemCount: reversedMessages.length,
                      itemBuilder: (context, index) {
                        final msg = reversedMessages[index];
                        return _buildMessageBubble(msg);
                      },
                    );
                  } else if (state is ChatError) {
                    return Center(child: Text("Error: ${state.error}"));
                  }
                  return Container();
                },
              ),
            ),
            // INPUT AREA
            const _ChatInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          "👋 Di hola para comenzar la adopción",
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isMe = msg.isMe;

    // Alineación y Colores
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final bgColor = isMe
        ? const Color(0xFFE91E63)
        : Colors.white; // Rosado PAWS vs Blanco
    final textColor = isMe ? Colors.white : Colors.black87;

    // Formato de hora manual (para no importar intl solo por esto)
    final timeStr =
        "${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}";

    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 280,
        ), // Ancho máximo de burbuja
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0), // Punta hacia abajo
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end, // Hora a la derecha
          children: [
            Text(msg.content, style: TextStyle(color: textColor, fontSize: 16)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : Colors.grey[500],
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  // Icono de "leído" (Doble Check) simulado
                  const Icon(Icons.done_all, size: 12, color: Colors.white70),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInput extends StatefulWidget {
  const _ChatInput();

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  final _controller = TextEditingController();

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    context.read<ChatBloc>().add(SendMessageEvent(_controller.text));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Protege en iPhone X+
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            // Campo de Texto
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: "Escribe un mensaje...",
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _send(), // Enviar al dar Enter teclado
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Botón Enviar
            CircleAvatar(
              backgroundColor: const Color(0xFFE91E63),
              radius: 24,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
