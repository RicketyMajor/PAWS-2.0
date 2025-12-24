import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/chat_bloc.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';

class ChatScreen extends StatelessWidget {
  final int matchId;
  final String peerName; // Nombre con quien hablas

  const ChatScreen({super.key, required this.matchId, required this.peerName});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ChatBloc(repository: RepositoryProvider.of<ChatRepository>(context))
            ..add(InitChat(matchId)),
      child: Scaffold(
        appBar: AppBar(title: Text(peerName)),
        body: Column(
          children: [
            // Lista de Mensajes
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state is ChatLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is ChatLoaded) {
                    // Auto-scroll al final
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      // Aquí podrías usar un ScrollController para ir al final
                    });

                    return ListView.builder(
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        final msg = state.messages[index];
                        return _buildMessageBubble(msg);
                      },
                    );
                  } else if (state is ChatError) {
                    return Center(child: Text(state.error));
                  }
                  return Container();
                },
              ),
            ),
            // Input
            const _ChatInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final align = msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = msg.isMe ? Colors.deepPurple : Colors.grey[300];
    final textColor = msg.isMe ? Colors.white : Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(msg.content, style: TextStyle(color: textColor)),
          ),
          Text(
            "${msg.createdAt.hour}:${msg.createdAt.minute}",
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: "Escribe un mensaje...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.deepPurple),
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}
