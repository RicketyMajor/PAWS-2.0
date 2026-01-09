import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';
import '../../../pets/data/matches_repository.dart';

// --- EVENTOS ---
abstract class ChatEvent extends Equatable {
  @override
  // CORRECCIÓN: Usar Object? aquí también
  List<Object?> get props => [];
}

class InitChat extends ChatEvent {
  final int matchId;
  final String? initialStatus;
  InitChat(this.matchId, {this.initialStatus});

  @override
  List<Object?> get props => [matchId, initialStatus];
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

class _ReceiveMessageEvent extends ChatEvent {
  final ChatMessage message;
  _ReceiveMessageEvent(this.message);

  @override
  List<Object?> get props => [message];
}

// --- ESTADOS ---
abstract class ChatState extends Equatable {
  @override
  // CORRECCIÓN CRÍTICA: Cambiar List<Object> por List<Object?>
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

  ChatLoaded({
    required this.messages,
    required this.matchId,
    required this.myUserId,
    this.isLocked = false,
    this.lockReason = '',
    this.error,
  });

  @override
  // Ahora esto coincide perfectamente con el padre
  List<Object?> get props => [
    messages,
    matchId,
    myUserId,
    isLocked,
    lockReason,
    error,
  ];

  ChatLoaded copyWith({
    List<ChatMessage>? messages,
    int? matchId,
    int? myUserId,
    bool? isLocked,
    String? lockReason,
    String? error,
  }) {
    return ChatLoaded(
      messages: messages ?? this.messages,
      matchId: matchId ?? this.matchId,
      myUserId: myUserId ?? this.myUserId,
      isLocked: isLocked ?? this.isLocked,
      lockReason: lockReason ?? this.lockReason,
      error: error,
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
  final _storage = const FlutterSecureStorage();

  StreamSubscription? _messagesSubscription;
  int _currentMatchId = 0;
  int _myUserId = 0;

  ChatBloc({required this.chatRepository, required this.matchesRepository})
    : super(ChatLoading()) {
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

        bool isLocked = false;
        String reason = '';

        if (event.initialStatus != null && event.initialStatus != 'accepted') {
          isLocked = true;
          if (event.initialStatus == 'pet_deleted')
            reason = 'La mascota fue eliminada.';
          else if (event.initialStatus == 'adopter_left')
            reason = 'El adoptante abandonó el chat.';
          else if (event.initialStatus == 'rescuer_left')
            reason = 'El rescatista abandonó el chat.';
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
            messages: [...currentState.messages, event.message],
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
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
