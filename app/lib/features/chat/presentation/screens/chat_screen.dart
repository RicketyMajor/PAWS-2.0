import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';
import '../../../pets/data/matches_repository.dart';
import '../../../reviews/data/reviews_repository.dart';
import '../bloc/chat_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../widgets/chat_bubble.dart';
import '../../../reviews/presentation/widgets/star_rating_input.dart';
import '../../../auth/data/auth_repository.dart';
// --- Imports para navegación ---
import '../../../pets/presentation/screens/pet_detail_screen.dart';
import '../../../user/presentation/screens/public_profile_screen.dart';
import '../../../pets/data/pets_repository.dart';
import '../../../user/data/user_repository.dart';

class ChatScreen extends StatefulWidget {
  final int matchId;
  final String peerName;
  final int peerId;
  final String? peerPhotoUrl;
  final int petId;
  final bool isPetDeleted;
  final bool isPeerLeft;
  final bool isRescuer;

  const ChatScreen({
    super.key,
    required this.matchId,
    required this.peerName,
    required this.peerId,
    required this.petId,
    this.peerPhotoUrl,
    this.isPetDeleted = false,
    this.isPeerLeft = false,
    this.isRescuer = false,
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
    _markChatAsRead(); // <--- ACCIÓN: Marcar como leído al entrar
  }

  Future<void> _loadMyUserId() async {
    // AHORA LO LEEMOS DESDE EL PROVIDER
    String? token = await context.read<AuthRepository>().getToken();
    if (token != null) {
      Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
      setState(() {
        _myUserId =
            decodedToken['user_id'] ??
            int.parse(decodedToken['sub'].toString());
      });
    }
  }

  // Llama al repositorio para actualizar el estado en el backend
  void _markChatAsRead() {
    context.read<ChatRepository>().markAsRead(widget.matchId);
  }

  @override
  Widget build(BuildContext context) {
    String? initialStatus;
    if (widget.isPetDeleted)
      initialStatus = 'pet_deleted';
    else if (widget.isPeerLeft)
      initialStatus = widget.isRescuer ? 'adopter_left' : 'rescuer_left';
    if (widget.isPeerLeft) initialStatus = 'peer_left';

    return BlocProvider(
      create: (context) =>
          ChatBloc(
            chatRepository: context.read<ChatRepository>(),
            matchesRepository: context.read<MatchesRepository>(),
            reviewsRepository: context.read<ReviewsRepository>(),
          )..add(
            InitChat(
              widget.matchId,
              initialStatus: initialStatus,
              isRescuer: widget.isRescuer,
            ),
          ),
      child: BlocListener<ChatBloc, ChatState>(
        listener: (context, state) {
          if (state is ChatLoaded) {
            // Feedback envío fallido (socket caído)
            if (state.error != null &&
                state.reportStatus != ReportStatus.failure &&
                state.reviewStatus != ReviewStatus.failure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.error!),
                  backgroundColor: Colors.orange.shade800,
                ),
              );
            }

            // Feedback Reportes
            if (state.reportStatus == ReportStatus.success) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Reporte enviado."),
                  backgroundColor: Colors.green,
                ),
              );
            } else if (state.reportStatus == ReportStatus.failure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Error reporte: ${state.error}"),
                  backgroundColor: Colors.red,
                ),
              );
            }

            // Feedback Reseñas
            if (state.reviewStatus == ReviewStatus.success) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("¡Calificación enviada! ⭐"),
                  backgroundColor: Colors.green,
                ),
              );
            } else if (state.reviewStatus == ReviewStatus.failure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Error al calificar: ${state.error}"),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: Color(0xFFE91E63),
                semanticLabel: 'Volver',
              ),
              tooltip: 'Volver',
              onPressed: () => Navigator.pop(context),
            ),
            // 1. EL TÍTULO AHORA ES UN BOTÓN HACIA EL PERFIL
            titleSpacing: 0, // Para acercar el nombre a la flecha
            title: InkWell(
              onTap: () async {
                // 1. Mostrar pantalla de carga
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: CircularProgressIndicator(color: Color(0xFFE91E63)),
                  ),
                );

                try {
                  // 2. Buscar al usuario completo
                  final user = await context.read<UserRepository>().getUserById(
                    widget.peerId,
                  );

                  if (context.mounted) {
                    Navigator.pop(context); // Quitar carga
                    // 3. Viajar a la pantalla
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PublicProfileScreen(user: user),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // Quitar carga
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "No se pudo cargar el perfil del usuario",
                        ),
                      ),
                    );
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: ImageHelper.getProvider(
                        widget.peerPhotoUrl,
                      ),
                      child: (widget.peerPhotoUrl == null)
                          ? Text(
                              widget.peerName.isNotEmpty
                                  ? widget.peerName[0].toUpperCase()
                                  : '?',
                            )
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
              ),
            ),
            actions: [
              // 2. BOTÓN DE LA MASCOTA
              IconButton(
                icon: const Icon(
                  Icons.pets,
                  color: Color(0xFFE91E63),
                  semanticLabel: "Ver mascota",
                ),
                tooltip: "Ver mascota",
                onPressed: () async {
                  // 1. Mostrar pantalla de carga
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFE91E63),
                      ),
                    ),
                  );

                  try {
                    // 2. Buscar la mascota completa
                    final pet = await context.read<PetsRepository>().getPetById(
                      widget.petId,
                    );

                    if (context.mounted) {
                      Navigator.pop(context); // Quitar carga
                      // 3. Viajar a la pantalla
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PetDetailScreen(pet: pet),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context); // Quitar carga
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("No se pudo cargar la mascota"),
                        ),
                      );
                    }
                  }
                },
              ),

              // 3. EL MENÚ DE LOS TRES PUNTOS (Tu código original intacto)
              BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  bool isLocked = (state is ChatLoaded && state.isLocked);
                  bool canRate = !widget.isPetDeleted;

                  return PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    onSelected: (value) {
                      if (value == 'rate') {
                        _showRatingDialog(context);
                      } else if (value == 'report') {
                        _showReportDialog(context);
                      } else if (value == 'unmatch') {
                        _confirmUnmatch(context, isLocked);
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      return [
                        if (canRate)
                          const PopupMenuItem(
                            value: 'rate',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.star_rate_rounded,
                                  color: Colors.amber,
                                ),
                                SizedBox(width: 8),
                                Text("Calificar"),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(Icons.flag_outlined, color: Colors.orange),
                              SizedBox(width: 8),
                              Text("Reportar usuario"),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'unmatch',
                          child: Row(
                            children: [
                              Icon(
                                isLocked ? Icons.delete_outline : Icons.block,
                                color: Colors.red,
                              ),
                              SizedBox(width: 8),
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
              Expanded(
                child: BlocBuilder<ChatBloc, ChatState>(
                  builder: (context, state) {
                    if (state is ChatLoading)
                      return const Center(child: CircularProgressIndicator());
                    if (state is ChatLoaded) {
                      if (state.messages.isEmpty) return _buildEmptyChat();

                      return ListView.builder(
                        controller: _scrollController,
                        reverse:
                            true, // Importante: index 0 es el ÚLTIMO mensaje (abajo)
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final msg = state.messages[index];
                          final isMe = msg.senderId == _myUserId;

                          // --- LÓGICA DEL VISTO ---
                          // Mostramos "Visto" SOLO si:
                          // 1. Es el mensaje más reciente (index == 0)
                          // 2. Lo envié yo (isMe)
                          // 3. Está marcado como leído en BD (msg.isRead)
                          bool showSeen = (index == 0 && isMe && msg.isRead);

                          return ChatBubble(
                            message: msg,
                            isMe: isMe,
                            isSeen: showSeen, // Pasamos el flag
                          );
                        },
                      );
                    }
                    if (state is ChatError)
                      return Center(child: Text(state.message));
                    return const SizedBox.shrink();
                  },
                ),
              ),
              BlocConsumer<ChatBloc, ChatState>(
                listener: (context, state) {},
                builder: (context, state) {
                  if (state is ChatLoaded && state.isLocked)
                    return _buildLockedWidget(state.lockReason);
                  if (state is! ChatLoaded) return const SizedBox.shrink();
                  return _buildInputArea(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ... (Resto de métodos: _showRatingDialog, _showReportDialog, etc. permanecen IGUAL)
  // COPIA AQUÍ EL RESTO DE TUS MÉTODOS DEL ARCHIVO ORIGINAL (_showRatingDialog, _confirmUnmatch, etc.)

  void _showRatingDialog(BuildContext chatContext) {
    double _currentRating = 0.0;
    String _comment = "";

    showDialog(
      context: chatContext,
      builder: (dialogContext) {
        return BlocProvider.value(
          value: BlocProvider.of<ChatBloc>(chatContext),
          child: StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text(
                  "Calificar Experiencia",
                  textAlign: TextAlign.center,
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Toca las estrellas para calificar",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      StarRatingInput(
                        rating: _currentRating,
                        size: 40,
                        onChanged: (val) {
                          setState(() => _currentRating = val);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentRating > 0
                            ? "$_currentRating Estrellas"
                            : "Selecciona una calificación",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _currentRating > 0
                              ? Colors.amber[800]
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: "Reseña (Opcional)",
                          hintText: "¿Cómo fue tu experiencia?",
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onChanged: (val) => _comment = val,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text(
                      "Cancelar",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  BlocBuilder<ChatBloc, ChatState>(
                    builder: (context, state) {
                      if (state is ChatLoaded &&
                          state.reviewStatus == ReviewStatus.loading) {
                        return const CircularProgressIndicator();
                      }
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE91E63),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _currentRating > 0
                            ? () {
                                context.read<ChatBloc>().add(
                                  SendReviewEvent(
                                    rating: _currentRating,
                                    comment: _comment,
                                  ),
                                );
                              }
                            : null,
                        child: const Text("Enviar Calificación"),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showReportDialog(BuildContext chatContext) {
    final _formKey = GlobalKey<FormState>();
    String selectedCategory = 'abuse';
    String description = '';

    final Map<String, String> categories = {
      'abuse': 'Maltrato Animal',
      'scam': 'Estafa / Fraude',
      'spam': 'Spam / Publicidad',
      'hate': 'Lenguaje Ofensivo / Odio',
      'other': 'Otro',
    };

    showDialog(
      context: chatContext,
      builder: (dialogContext) {
        return BlocProvider.value(
          value: BlocProvider.of<ChatBloc>(chatContext),
          child: AlertDialog(
            title: const Text("Reportar Usuario"),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Tu reporte es anónimo y será revisado por un administrador.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: "Motivo",
                        border: OutlineInputBorder(),
                      ),
                      items: categories.entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) selectedCategory = val;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: "Detalles adicionales",
                        border: OutlineInputBorder(),
                        hintText: "Describe brevemente la situación...",
                      ),
                      maxLines: 3,
                      onChanged: (val) => description = val,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Por favor, añade detalles.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  "Cancelar",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state is ChatLoaded &&
                      state.reportStatus == ReportStatus.loading) {
                    return const CircularProgressIndicator();
                  }

                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        context.read<ChatBloc>().add(
                          ReportUserEvent(
                            reportedId: widget.peerId,
                            category: selectedCategory,
                            description: description,
                          ),
                        );
                      }
                    },
                    child: const Text("Enviar Reporte"),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
            CircleAvatar(
              backgroundColor: const Color(0xFFE91E63),
              radius: 22,
              child: IconButton(
                icon: const Icon(
                  Icons.send,
                  color: Colors.white,
                  size: 20,
                  semanticLabel: 'Enviar mensaje',
                ),
                tooltip: 'Enviar mensaje',
                onPressed: () => _sendMessage(context),
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
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
