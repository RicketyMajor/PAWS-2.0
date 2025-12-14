import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/chat_repository.dart';
import '../bloc/chat_bloc.dart';
import '../../domain/message_model.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Inyectamos el ChatBloc y el repositorio AQUÍ mismo
    return RepositoryProvider(
      create: (context) => ChatRepository(),
      child: BlocProvider(
        create: (context) =>
            ChatBloc(context.read<ChatRepository>())..add(ConnectChat()),
        child: const _ChatView(),
      ),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView();

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _textController = TextEditingController();

  void _sendMessage() {
    if (_textController.text.trim().isNotEmpty) {
      context.read<ChatBloc>().add(SendMessage(_textController.text));
      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Chat Global"), centerTitle: true),
      body: Column(
        children: [
          // 1. Lista de Mensajes
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state is ChatConnecting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is ChatError) {
                  return Center(child: Text("Error: ${state.error}"));
                }
                if (state is ChatActive) {
                  if (state.messages.isEmpty) {
                    return const Center(child: Text("¡Di hola!"));
                  }

                  return ListView.builder(
                    reverse: true, // Para que el último mensaje salga abajo
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final msg = state.messages[index];
                      return _ChatBubble(message: msg);
                    },
                  );
                }
                return const Center(child: Text("Conectando..."));
              },
            ),
          ),

          // 2. Input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: "Escribe un mensaje...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFFE91E63)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    // Detectamos si es un mensaje de alerta del sistema (Evil PAWS)
    final isSystem = message.text.contains("🚫");

    return Align(
      alignment: isSystem ? Alignment.center : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSystem ? Colors.red[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: isSystem ? Border.all(color: Colors.red) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isSystem ? Colors.red[900] : Colors.black87,
                fontWeight: isSystem ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
