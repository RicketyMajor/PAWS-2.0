import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';
import '../../../pets/data/matches_repository.dart';
import '../../../reviews/data/reviews_repository.dart'; // <--- IMPORTANTE

// --- ENUMS ---
enum ReportStatus { initial, loading, success, failure }

enum ReviewStatus { initial, loading, success, failure } // <--- NUEVO

// --- EVENTOS ---
abstract class ChatEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class InitChat extends ChatEvent {
  final int matchId;
  final String? initialStatus;
  final bool isRescuer;

  InitChat(this.matchId, {this.initialStatus, this.isRescuer = false});
  @override
  List<Object?> get props => [matchId, initialStatus, isRescuer];
}

class SendMessageEvent extends ChatEvent {
  final String content;
  SendMessageEvent(this.content);
  @override
  List<Object?> get props => [content];
}

class UnmatchChatEvent extends ChatEvent {
  UnmatchChatEvent();
}

class ReportUserEvent extends ChatEvent {
  final int reportedId;
  final String category;
  final String description;

  ReportUserEvent({
    required this.reportedId,
    required this.category,
    required this.description,
  });
  @override
  List<Object?> get props => [reportedId, category, description];
}

// --- NUEVO EVENTO DE RESEÑA ---
class SendReviewEvent extends ChatEvent {
  final double rating;
  final String comment;

  SendReviewEvent({required this.rating, required this.comment});

  @override
  List<Object?> get props => [rating, comment];
}

class _ReceiveMessageEvent extends ChatEvent {
  final ChatMessage message;
  _ReceiveMessageEvent(this.message);
  @override
  List<Object?> get props => [message];
}

// --- ESTADOS ---
abstract class ChatState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
  final List<ChatMessage> messages;
  final int matchId;
  final int myUserId;
  final bool isLocked;
  final String lockReason;
  final String? error;

  final ReportStatus reportStatus;
  final ReviewStatus reviewStatus; // <--- NUEVO CAMPO

  ChatLoaded({
    required this.messages,
    required this.matchId,
    required this.myUserId,
    this.isLocked = false,
    this.lockReason = '',
    this.error,
    this.reportStatus = ReportStatus.initial,
    this.reviewStatus = ReviewStatus.initial,
  });

  @override
  List<Object?> get props => [
    messages,
    matchId,
    myUserId,
    isLocked,
    lockReason,
    error,
    reportStatus,
    reviewStatus,
  ];

  ChatLoaded copyWith({
    List<ChatMessage>? messages,
    int? matchId,
    int? myUserId,
    bool? isLocked,
    String? lockReason,
    String? error,
    ReportStatus? reportStatus,
    ReviewStatus? reviewStatus,
  }) {
    return ChatLoaded(
      messages: messages ?? this.messages,
      matchId: matchId ?? this.matchId,
      myUserId: myUserId ?? this.myUserId,
      isLocked: isLocked ?? this.isLocked,
      lockReason: lockReason ?? this.lockReason,
      error: error,
      reportStatus: reportStatus ?? this.reportStatus,
      reviewStatus: reviewStatus ?? this.reviewStatus,
    );
  }
}

class ChatError extends ChatState {
  final String message;
  ChatError(this.message);
  @override
  List<Object?> get props => [message];
}

// --- BLOC ---
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository chatRepository;
  final MatchesRepository matchesRepository;
  final ReviewsRepository reviewsRepository; // <--- INYECCIÓN
  final _storage = const FlutterSecureStorage();

  StreamSubscription? _messagesSubscription;
  int _currentMatchId = 0;
  int _myUserId = 0;

  ChatBloc({
    required this.chatRepository,
    required this.matchesRepository,
    required this.reviewsRepository, // <--- REQUERIDO
  }) : super(ChatLoading()) {
    on<InitChat>((event, emit) async {
      emit(ChatLoading());
      _currentMatchId = event.matchId;

      try {
        final token = await _storage.read(key: 'jwt_token');
        if (token != null) {
          final decodedToken = JwtDecoder.decode(token);
          _myUserId = decodedToken['user_id'] ?? int.parse(decodedToken['sub']);
        }

        final historyJson = await chatRepository.getHistory(_currentMatchId);
        final history = historyJson
            .map((json) => ChatMessage.fromJson(json, _myUserId))
            .toList();
        history.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        bool isLocked = false;
        String reason = '';

        if (event.initialStatus != null && event.initialStatus != 'accepted') {
          isLocked = true;
          if (event.initialStatus == 'pet_deleted') {
            reason = event.isRescuer
                ? 'Has eliminado la publicación de esta mascota.'
                : 'La publicación de esta mascota ha sido eliminada.';
          } else if (event.initialStatus == 'adopter_left')
            reason = 'El adoptante abandonó el chat.';
          else if (event.initialStatus == 'rescuer_left')
            reason = 'El rescatista abandonó el chat.';
          else if (event.initialStatus == 'peer_left')
            reason = 'El otro usuario abandonó el chat.';
          else
            reason = 'Chat finalizado.';
        }

        emit(
          ChatLoaded(
            messages: history,
            matchId: _currentMatchId,
            myUserId: _myUserId,
            isLocked: isLocked,
            lockReason: reason,
          ),
        );

        await chatRepository.connect();

        _messagesSubscription?.cancel();
        _messagesSubscription = chatRepository.messages.listen((dynamic data) {
          try {
            final decoded = jsonDecode(data);
            if (decoded['type'] == 'new_message') {
              final payload = decoded['payload'];
              if (payload['match_id'] == _currentMatchId) {
                final newMsg = ChatMessage.fromJson(payload, _myUserId);
                add(_ReceiveMessageEvent(newMsg));
              }
            } else if (decoded['type'] == 'error') {
              // Si el backend rechaza el mensaje, lo imprimimos (¡Aquí podrías mostrar un SnackBar luego!)
              print("ERROR DEL BACKEND WS: ${decoded['payload']['message']}");
            }
          } catch (e) {
            print("Error parseando mensaje WS: $e");
          }
        });
      } catch (e) {
        emit(ChatError("Error cargando chat: $e"));
      }
    });

    on<SendMessageEvent>((event, emit) {
      final currentState = state;
      if (currentState is ChatLoaded) {
        if (currentState.isLocked) return;
        try {
          chatRepository.sendMessage(_currentMatchId, event.content);
        } catch (e) {
          print("Error enviando: $e");
        }
      }
    });

    on<_ReceiveMessageEvent>((event, emit) {
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        emit(
          currentState.copyWith(
            messages: [event.message, ...currentState.messages],
          ),
        );
      }
    });

    on<UnmatchChatEvent>((event, emit) async {
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        try {
          await matchesRepository.unmatch(_currentMatchId);
          emit(
            currentState.copyWith(
              isLocked: true,
              lockReason: 'Has abandonado este chat.',
              error: null,
            ),
          );
        } catch (e) {
          emit(
            currentState.copyWith(
              error: "No se pudo salir del chat: ${e.toString()}",
            ),
          );
        }
      }
    });

    // --- NUEVO HANDLER DE REPORTE ---
    on<ReportUserEvent>((event, emit) async {
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;

        // 1. Emitir estado de carga (sin borrar mensajes)
        emit(currentState.copyWith(reportStatus: ReportStatus.loading));

        try {
          // 2. Llamar al repositorio
          await chatRepository.reportUser(
            reportedId: event.reportedId,
            matchId: _currentMatchId,
            category: event.category,
            description: event.description,
          );

          // 3. Éxito
          emit(currentState.copyWith(reportStatus: ReportStatus.success));

          // Opcional: Volver a initial para limpiar el flag
          emit(currentState.copyWith(reportStatus: ReportStatus.initial));
        } catch (e) {
          // 4. Error
          emit(
            currentState.copyWith(
              reportStatus: ReportStatus.failure,
              error: e.toString(),
            ),
          );
          // Limpiar error después
          emit(
            currentState.copyWith(
              reportStatus: ReportStatus.initial,
              error: null,
            ),
          );
        }
      }
    });
    // --- HANDLER DE RESEÑAS (NUEVO) ---
    on<SendReviewEvent>((event, emit) async {
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        emit(currentState.copyWith(reviewStatus: ReviewStatus.loading));

        try {
          await reviewsRepository.createReview(
            matchId: _currentMatchId,
            rating: event.rating,
            comment: event.comment,
          );
          emit(currentState.copyWith(reviewStatus: ReviewStatus.success));
          // Reset status
          emit(currentState.copyWith(reviewStatus: ReviewStatus.initial));
        } catch (e) {
          emit(
            currentState.copyWith(
              reviewStatus: ReviewStatus.failure,
              error: e.toString(),
            ),
          );
          emit(
            currentState.copyWith(
              reviewStatus: ReviewStatus.initial,
              error: null,
            ),
          );
        }
      }
    });
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
