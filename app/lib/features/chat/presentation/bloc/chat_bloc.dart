import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';

// --- EVENTOS ---
abstract class ChatEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class InitChat extends ChatEvent {
  final int matchId;
  InitChat(this.matchId);
}

class SendMessageEvent extends ChatEvent {
  final String content;
  SendMessageEvent(this.content);
}

class _ReceiveMessageEvent extends ChatEvent {
  final ChatMessage message;
  _ReceiveMessageEvent(this.message);
}

// --- ESTADOS ---
abstract class ChatState extends Equatable {
  @override
  List<Object> get props => [];
}

class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
  final List<ChatMessage> messages;
  final int matchId;

  ChatLoaded({required this.messages, required this.matchId});

  @override
  List<Object> get props => [messages, matchId];
}

class ChatError extends ChatState {
  final String error;
  ChatError(this.error);
}

// --- BLOC ---
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository repository;
  StreamSubscription? _wsSubscription;
  int _currentMatchId = 0;

  ChatBloc({required this.repository}) : super(ChatLoading()) {
    // 1. Iniciar: Cargar Historial + Conectar WS
    on<InitChat>((event, emit) async {
      _currentMatchId = event.matchId;
      emit(ChatLoading());

      try {
        // A. Cargar Historial DB
        final history = await repository.getHistory(event.matchId);
        emit(ChatLoaded(messages: history, matchId: event.matchId));

        // B. Conectar WebSocket
        final stream = await repository.connectToChat();

        // C. Escuchar WebSocket
        _wsSubscription?.cancel();
        _wsSubscription = stream.listen((data) {
          // Cuando llega un mensaje del servidor
          // NOTA: Tu backend devuelve solo el string del contenido o un JSON.
          // Asumamos que devuelve el texto por ahora según tu ws_handler.go
          // O mejor, si ajustaste el backend para devolver JSON completo, parsealo aquí.

          // Simulación simple para MVP: Creamos objeto local
          // En producción, el backend debería devolver el objeto Message completo creado en BD
          final newMsg = ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch,
            matchId: _currentMatchId,
            senderId:
                0, // No sabemos el senderID exacto solo con string, asumimos "el otro"
            content: data.toString(), // El backend manda bytes/string
            isRead: false,
            createdAt: DateTime.now(),
            isMe: false, // Asumimos que lo que llega por WS es del otro
          );

          add(_ReceiveMessageEvent(newMsg));
        }, onError: (error) => print("WS Error: $error"));
      } catch (e) {
        emit(ChatError(e.toString()));
      }
    });

    // 2. Enviar Mensaje
    on<SendMessageEvent>((event, emit) async {
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;

        // Enviar por WS
        repository.sendMessage(_currentMatchId, event.content);

        // Optimistic Update: Lo agregamos a la lista localmente como "mío"
        final myMsg = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch,
          matchId: _currentMatchId,
          senderId: 999, // ID temporal
          content: event.content,
          isRead: false,
          createdAt: DateTime.now(),
          isMe: true,
        );

        emit(
          ChatLoaded(
            messages: [...currentState.messages, myMsg],
            matchId: _currentMatchId,
          ),
        );
      }
    });

    // 3. Recibir Mensaje (Evento interno)
    on<_ReceiveMessageEvent>((event, emit) {
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        emit(
          ChatLoaded(
            messages: [...currentState.messages, event.message],
            matchId: _currentMatchId,
          ),
        );
      }
    });
  }

  @override
  Future<void> close() {
    _wsSubscription?.cancel();
    repository.disconnect();
    return super.close();
  }
}
