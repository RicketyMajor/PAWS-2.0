import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart'; // <--- Necesitamos esto
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
  final int myUserId; // Agregamos esto para facilitar la UI

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
        // A. Obtener mi ID del token (para saber cuál mensaje es mío)
        final token = await _storage.read(key: 'jwt_token');
        if (token != null) {
          Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
          // Asegúrate que tu token tiene el campo 'user_id' o 'sub' como número
          // Ajusta esto según cómo genere el token tu Go
          _myUserId = (decodedToken['user_id'] ?? decodedToken['sub'] ?? 0)
              .toInt();
        }

        // B. Cargar Historial (HTTP)
        final rawHistory = await repository.getRawHistory(event.matchId);
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
        await repository.connect(); // Conecta el socket global

        _wsSubscription?.cancel();
        _wsSubscription = repository.messages.listen((data) {
          try {
            // El backend envía un string JSON
            final decoded = jsonDecode(data);

            // Verificamos estructura del Hub Go: { "type": "...", "payload": ... }
            if (decoded['type'] == 'new_message') {
              final payload = decoded['payload'];

              // Verificamos que el mensaje sea para ESTE chat
              if (payload['match_id'] == _currentMatchId) {
                final newMsg = ChatMessage.fromJson(payload, _myUserId);
                add(_ReceiveMessageEvent(newMsg));
              }
            }
          } catch (e) {
            print("Error parseando mensaje WS: $e");
          }
        }, onError: (error) => print("WS Error: $error"));
      } catch (e) {
        print("Error InitChat: $e");
        emit(ChatError("No se pudo conectar al chat."));
      }
    });

    // 2. ENVIAR MENSAJE
    on<SendMessageEvent>((event, emit) async {
      if (state is ChatLoaded) {
        // Enviar por WS (El backend lo guardará y nos lo devolverá por el stream 'new_message')
        // NOTA: Podríamos hacer optimistic update aquí, pero como el WS es rápido,
        // esperaremos a que vuelva el mensaje del servidor para confirmar que se guardó.
        repository.sendMessage(_currentMatchId, event.content);
      }
    });

    // 3. RECIBIR MENSAJE (Viene del listen del socket)
    on<_ReceiveMessageEvent>((event, emit) {
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        // Agregamos al final
        emit(
          ChatLoaded(
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
