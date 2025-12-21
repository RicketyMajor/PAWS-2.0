import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/chat_repository.dart';
import '../../domain/message_model.dart';

// --- EVENTOS ---
abstract class ChatEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class ConnectChat extends ChatEvent {}

class SendMessage extends ChatEvent {
  final String text;
  SendMessage(this.text);
}

class ReceiveMessage extends ChatEvent {
  final String text;
  ReceiveMessage(this.text);
}

class DisconnectChat extends ChatEvent {}

// --- ESTADOS ---
abstract class ChatState extends Equatable {
  @override
  List<Object> get props => [];
}

class ChatInitial extends ChatState {}

class ChatConnecting extends ChatState {}

class ChatActive extends ChatState {
  final List<ChatMessage> messages;

  // CORRECCIÓN: Borramos 'const' aquí
  ChatActive(this.messages);

  @override
  List<Object> get props => [messages];
}

class ChatError extends ChatState {
  final String error;

  // CORRECCIÓN: Borramos 'const' aquí
  ChatError(this.error);

  @override
  List<Object> get props => [error];
}

// --- BLOC ---
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository repository;
  StreamSubscription? _subscription;

  ChatBloc(this.repository) : super(ChatInitial()) {
    // 1. Conectar
    on<ConnectChat>((event, emit) async {
      emit(ChatConnecting());
      try {
        final stream = await repository.connect();

        // Escuchar el stream del servidor
        _subscription = stream.listen(
          (data) {
            add(ReceiveMessage(data.toString()));
          },
          onError: (error) {
            // No podemos emitir estados desde el listen directamente,
            // así que idealmente dispararíamos un evento de error.
            // Por simplicidad, solo imprimimos.
            print("Error WS: $error");
          },
        );

        emit(ChatActive([])); // Chat vacío al inicio
      } catch (e) {
        emit(ChatError("No se pudo conectar: $e"));
      }
    });

    // 2. Enviar Mensaje (Yo escribo)
    on<SendMessage>((event, emit) {
      if (state is ChatActive) {
        final currentMessages = List<ChatMessage>.from(
          (state as ChatActive).messages,
        );

        // Agregamos mi mensaje a la lista visualmente
        // (Nota: Como tu backend hace "Echo", recibiremos el mensaje de vuelta también.
        // Para no duplicarlo, podríamos esperar a que vuelva, pero para UI fluida lo mostramos ya).
        // *Estrategia PAWS:* Tu backend devuelve el mensaje a TODOS.
        // Si lo agregamos aquí, cuando llegue de vuelta lo veremos doble.
        // -> MEJOR ESTRATEGIA: Enviamos al server y NO lo agregamos localmente todavía.
        //    Esperamos a que el servidor nos lo devuelva (ReceiveMessage).

        repository.sendMessage(event.text);
      }
    });

    // 3. Recibir Mensaje (Llega del servidor)
    on<ReceiveMessage>((event, emit) {
      if (state is ChatActive) {
        final currentMessages = List<ChatMessage>.from(
          (state as ChatActive).messages,
        );

        // Aquí asumimos que todo lo que llega es mensaje.
        // En un chat real validaríamos si el ID del emisor soy yo.
        // Como es un chat simple de prueba:
        // Si el mensaje empieza con [SYSTEM], es del sistema (Evil PAWS).

        bool isSystem = event.text.contains("[SYSTEM]");

        // Truco visual simple: Si lo acabamos de mandar nosotros, no tenemos forma fácil de saberlo
        // sin un ID en el mensaje JSON. Por ahora, marcaremos todos como "recibidos" (izquierda)
        // salvo que hagamos una lógica compleja.
        // Para este prototipo: Todo a la izquierda.

        currentMessages.insert(
          0,
          ChatMessage(
            // Insertamos al inicio (lista invertida)
            text: event.text,
            isMe: false, // Por defecto gris
            timestamp: DateTime.now(),
          ),
        );

        emit(ChatActive(currentMessages));
      }
    });

    // 4. Desconectar
    on<DisconnectChat>((event, emit) {
      _subscription?.cancel();
      repository.disconnect();
      emit(ChatInitial());
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    repository.disconnect();
    return super.close();
  }
}
