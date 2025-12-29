import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/chat_bloc.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';
import '../../../social/data/social_repository.dart';

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
          title: Text(peerName),
          actions: [
            // --- MENÚ DE CONFIANZA ---
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'report') {
                  _showReportDialog(context);
                } else if (value == 'review') {
                  _showReviewDialog(context);
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem(
                    value: 'review',
                    child: Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber),
                        SizedBox(width: 8),
                        Text('Calificar Experiencia'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Reportar Usuario'),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
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

  // --- DIÁLOGO DE REPORTE ---
  void _showReportDialog(BuildContext context) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reportar Usuario"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Tu seguridad es prioridad. Este reporte es anónimo."),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: "Describe el motivo (Estafa, ofensivo...)",
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                // Instanciamos el repo directo (o úsalo con RepositoryProvider si prefieres)
                final repo = SocialRepository();
                // OJO: Aquí deberíamos pasar el ID real del usuario reportado.
                // Como tenemos matchId, en el backend podríamos deducirlo.
                // Por ahora pasamos matchId como placeholder si tu backend lo acepta,
                // o pasamos 0 y ajustamos backend.
                await repo.createReport(
                  reportedId: 999,
                  reason: reasonController.text,
                );

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Reporte enviado. Gracias.")),
                );
              } catch (e) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text(
              "REPORTAR",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // --- DIÁLOGO DE RESEÑA ---
  void _showReviewDialog(BuildContext context) {
    int _rating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Calificar Adopción"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("¿Qué tal fue tu experiencia?"),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < _rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 30,
                      ),
                      onPressed: () {
                        setState(() => _rating = index + 1);
                      },
                    );
                  }),
                ),
                TextField(
                  controller: commentController,
                  decoration: const InputDecoration(
                    hintText: "Comentario (Opcional)",
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancelar"),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final repo = SocialRepository();
                    await repo.createReview(
                      matchId: matchId,
                      rating: _rating,
                      comment: commentController.text,
                    );
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("¡Gracias por tu opinión!")),
                    );
                  } catch (e) {
                    // ... manejo error
                  }
                },
                child: const Text("ENVIAR"),
              ),
            ],
          );
        },
      ),
    );
  }
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
