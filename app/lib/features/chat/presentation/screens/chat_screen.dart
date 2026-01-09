import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Imports de Capa de Datos y Dominio
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';
import '../../../pets/data/matches_repository.dart'; // <--- NUEVO IMPORT

// Imports de Presentación (Blocs y Widgets)
import '../bloc/chat_bloc.dart';
import '../../../../core/utils/image_helper.dart';

class ChatScreen extends StatefulWidget {
  final int matchId;
  final String peerName;
  final int peerId;
  final String? peerPhotoUrl;

  // --- FLAGS DE ESTADO (Para bloqueo inicial) ---
  final bool isPetDeleted;
  final bool isPeerLeft;

  const ChatScreen({
    super.key,
    required this.matchId,
    required this.peerName,
    required this.peerId,
    this.peerPhotoUrl,
    this.isPetDeleted = false,
    this.isPeerLeft = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _storage = const FlutterSecureStorage();
  int? _myUserId;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
  }

  Future<void> _loadMyUserId() async {
    String? token = await _storage.read(key: 'jwt_token');
    if (token != null) {
      Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
      setState(() {
        _myUserId = decodedToken['user_id'] ?? int.parse(decodedToken['sub']);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determinamos el estado inicial para pasarlo al BLoC
    String? initialStatus;
    if (widget.isPetDeleted)
      initialStatus = 'pet_deleted';
    else if (widget.isPeerLeft)
      initialStatus = 'peer_left'; // El BLoC interpretará esto

    return BlocProvider(
      create: (context) => ChatBloc(
        chatRepository: context.read<ChatRepository>(),
        matchesRepository: context
            .read<MatchesRepository>(), // <--- INYECCIÓN DE REPO
      )..add(InitChat(widget.matchId, initialStatus: initialStatus)),

      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFFE91E63)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey[200],
                backgroundImage: ImageHelper.getProvider(widget.peerPhotoUrl),
                child: (widget.peerPhotoUrl == null)
                    ? Text(widget.peerName[0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.peerName,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            // --- MENÚ DE OPCIONES ---
            BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                // Verificamos si está bloqueado para cambiar el texto,
                // pero YA NO ocultamos el botón.
                bool isLocked = (state is ChatLoaded && state.isLocked);

                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  onSelected: (value) {
                    if (value == 'unmatch') {
                      _confirmUnmatch(context, isLocked);
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      // La opción aparece SIEMPRE
                      PopupMenuItem(
                        value: 'unmatch',
                        child: Row(
                          children: [
                            // Icono y texto cambian según el estado para dar mejor contexto
                            Icon(
                              isLocked ? Icons.delete_outline : Icons.block,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isLocked
                                  ? 'Eliminar de mi lista'
                                  : 'Salir del chat',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // --- LISTA DE MENSAJES ---
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state is ChatLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is ChatLoaded) {
                    if (state.messages.isEmpty) {
                      return _buildEmptyChat();
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      reverse:
                          true, // Importante: Mensajes nuevos abajo (si la lista viene ordenada desc)
                      // Ojo: Si tu ChatBloc añade al final, reverse debe ser false con controlador al final.
                      // Ajusta esto según tu lógica actual de ordenamiento.
                      // Asumiré orden cronológico (index 0 = antiguo) -> reverse: false + jumpToBottom
                      // O si usas reverse: true (index 0 = nuevo).
                      // MANTENDRÉ TU LOGICA ORIGINAL DE LISTVIEW SI LA TIENES DEFINIDA
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        final msg = state.messages[index];
                        final isMe = msg.senderId == _myUserId;
                        return _buildMessageBubble(msg, isMe);
                      },
                    );
                  } else if (state is ChatError) {
                    return Center(child: Text(state.message));
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),

            // --- BARRA DE INPUT O MENSAJE DE BLOQUEO ---
            BlocConsumer<ChatBloc, ChatState>(
              listener: (context, state) {
                // Escuchar si se bloqueó para hacer scroll o mostrar aviso
                if (state is ChatLoaded && state.messages.isNotEmpty) {
                  // Scroll al fondo al recibir mensaje (opcional)
                  // _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                }
              },
              builder: (context, state) {
                // 1. Si el chat está bloqueado, mostrar aviso
                if (state is ChatLoaded && state.isLocked) {
                  return _buildLockedWidget(state.lockReason);
                }

                // 2. Si está cargando o error, no mostrar input
                if (state is! ChatLoaded) return const SizedBox.shrink();

                // 3. Si está activo, mostrar Input normal
                return _buildInputArea(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildLockedWidget(String reason) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.grey[200],
      child: Column(
        children: [
          Icon(Icons.lock_outline, color: Colors.grey[500], size: 30),
          const SizedBox(height: 8),
          Text(
            reason.isNotEmpty ? reason : "El chat ya no está disponible.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "No puedes enviar más mensajes en esta conversación.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          children: [
            // Botón de adjuntar (Opcional, si lo tenías)
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.grey),
              onPressed: () {},
            ),

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
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: "Escribe un mensaje...",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(context),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Botón Enviar
            CircleAvatar(
              backgroundColor: const Color(0xFFE91E63),
              radius: 22,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: () => _sendMessage(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFE91E63) : Colors.grey[200],
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
              msg.content,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(msg.createdAt),
              style: TextStyle(
                color: isMe ? Colors.white70 : Colors.black54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mark_chat_unread_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          const Text(
            "Comienza la conversación 👋",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _sendMessage(BuildContext context) {
    if (_controller.text.trim().isEmpty) return;
    context.read<ChatBloc>().add(SendMessageEvent(_controller.text.trim()));
    _controller.clear();
  }

  void _confirmUnmatch(BuildContext context, bool isLocked) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isLocked ? "¿Eliminar chat?" : "¿Salir del chat?"),
        content: Text(
          isLocked
              ? "Este chat ya no está activo. Si lo eliminas, desaparecerá de tu lista permanentemente."
              : "Si sales, la conversación se cerrará y no podrán enviarse más mensajes.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Enviamos el evento para borrarlo/salir
              context.read<ChatBloc>().add(UnmatchChatEvent());
            },
            child: Text(
              isLocked ? "Eliminar" : "Salir",
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    // Helper simple para hora. Puedes usar intl si lo prefieres.
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
