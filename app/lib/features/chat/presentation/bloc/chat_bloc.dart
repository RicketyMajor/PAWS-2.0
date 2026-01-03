import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
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
  final int myUserId;

  ChatLoaded({
    required this.messages,
    required this.matchId,
    required this.myUserId,
  });

  @override
  List<Object> get props => [messages, matchId, myUserId];
}

class ChatError extends ChatState {
  final String error;
  ChatError(this.error);
}

// --- BLOC ---
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository repository;
  StreamSubscription? _wsSubscription;
  final _storage = const FlutterSecureStorage();

  int _currentMatchId = 0;
  int _myUserId = 0;

  ChatBloc({required this.repository}) : super(ChatLoading()) {
    // 1. INICIAR CHAT
    on<InitChat>((event, emit) async {
      _currentMatchId = event.matchId;
      emit(ChatLoading());

      try {
        // A. Obtener mi ID del token (para saber qué mensajes son míos: isMe)
        final token = await _storage.read(key: 'jwt_token');
        if (token != null) {
          Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
          // Buscamos 'user_id' o 'sub' y lo convertimos a int de forma segura
          final idVal = decodedToken['user_id'] ?? decodedToken['sub'] ?? 0;
          _myUserId = (idVal is int)
              ? idVal
              : int.tryParse(idVal.toString()) ?? 0;
        }

        // B. Cargar Historial (HTTP)
        // Usamos la función corregida 'getHistory' que retorna JSON crudo
        final rawHistory = await repository.getHistory(event.matchId);

        // Mapeamos JSON -> Modelo (inyectando _myUserId)
        final List<ChatMessage> history = rawHistory
            .map((json) => ChatMessage.fromJson(json, _myUserId))
            .toList();

        emit(
          ChatLoaded(
            messages: history,
            matchId: _currentMatchId,
            myUserId: _myUserId,
          ),
        );

        // C. Conectar y Escuchar WebSocket
        await repository.connect();

        _wsSubscription?.cancel();
        _wsSubscription = repository.messages.listen((data) {
          try {
            final decoded = jsonDecode(data);
            // Validamos el protocolo { "type": "new_message", "payload": ... }
            if (decoded['type'] == 'new_message') {
              final payload = decoded['payload'];

              // Solo procesamos si pertenece a este Match
              if (payload['match_id'] == _currentMatchId) {
                final newMsg = ChatMessage.fromJson(payload, _myUserId);
                add(_ReceiveMessageEvent(newMsg));
              }
            }
          } catch (e) {
            print("Error parseando mensaje WS: $e");
          }
        }, onError: (error) => print("❌ WS Error Stream: $error"));
      } catch (e) {
        print("Error InitChat: $e");
        emit(ChatError("No se pudo conectar al chat."));
      }
    });

    // 2. ENVIAR MENSAJE
    on<SendMessageEvent>((event, emit) {
      if (state is ChatLoaded) {
        repository.sendMessage(_currentMatchId, event.content);
      }
    });

    // 3. RECIBIR MENSAJE EN TIEMPO REAL
    on<_ReceiveMessageEvent>((event, emit) {
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        emit(
          ChatLoaded(
            // Agregamos el mensaje nuevo al final de la lista
            messages: [...currentState.messages, event.message],
            matchId: _currentMatchId,
            myUserId: _myUserId,
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
