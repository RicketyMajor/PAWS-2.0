import 'dart:convert';
import 'package:dio/dio.dart'; // <--- Necesario para HTTP
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/message_model.dart'; // <--- Importar modelo

class ChatRepository {
  WebSocketChannel? _channel;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Dio _dio = Dio(); // Cliente HTTP

  Stream<dynamic> get messages => _channel?.stream ?? const Stream.empty();

  // 1. CONECTAR
  Future<void> connect() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) throw Exception('No authentication token found');

    // Construcción de la URL:
    // Asumimos que ApiConstants.wsUrl es "ws://10.0.2.2:8080/api/v1"
    // El endpoint en Go es "/ws"
    final uri = Uri.parse('${ApiConstants.wsUrl}/ws');

    try {
      // IMPORTANTE: Usamos IOWebSocketChannel para poder enviar Headers
      // Esto es crucial porque tu middleware de Go espera el token aquí.
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
        pingInterval: const Duration(seconds: 10), // Keep-alive automático
      );

      // Esperamos el primer dato o error para validar conexión
      // (Opcional, pero ayuda a debuggear rápido)
      print("Intentando conectar WebSocket a $uri");
    } catch (e) {
      print("Error conectando WS: $e");
      rethrow;
    }
  }

  Future<List<ChatMessage>> getHistory(int matchId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      // Endpoint: /matches/:id/messages
      // Nota: Tu backend usa /matches/:id/messages en socialHandler
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/$matchId/messages',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        // Necesitamos el ID del usuario para saber cuáles son míos
        // Decodificamos el token temporalmente aquí o lo pasamos como argumento
        // Para simplificar, asumimos que el BLoC hará la distinción de "isMe",
        // aquí solo devolvemos los datos crudos mapeados.
        // PERO: El modelo ChatMessage.fromJson pide myUserId.
        // HACK MVP: Pasamos 0 por ahora y dejamos que el BLoC lo arregle,
        // o mejor, decodificamos el token aquí.

        // Estrategia BLoC: El Repo devuelve List<Map>, el Bloc convierte a Modelo.
        // Estrategia Repo (Mejor):
        List<dynamic> data = response.data;
        // Retornamos la lista cruda y dejamos que el BLoC, que sabe el ID, convierta.
        // O simplificamos el modelo.

        // Vamos a devolver la lista de mapas para no complicar el repo con lógica de IDs
        // Cambiaremos la firma del método un poco abajo en el BLoC.
        List<ChatMessage> messages = [];
        // (La conversión real la haremos en el BLoC para tener el userId)
        return [];
      }
      return [];
    } catch (e) {
      throw Exception('Error cargando historial: $e');
    }
  }

  // Helper para hacer la petición HTTP cruda y que el Bloc procese
  Future<List<dynamic>> getRawHistory(int matchId) async {
    final token = await _storage.read(key: 'jwt_token');
    final response = await _dio.get(
      '${ApiConstants.baseUrl}/matches/$matchId/messages',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data;
  }

  // 2. ENVIAR MENSAJE
  void sendMessage(int matchID, String content) {
    if (_channel != null) {
      // Formato JSON que espera tu Hub.go (InputMessage)
      final message = jsonEncode({"match_id": matchID, "content": content});
      _channel!.sink.add(message);
    } else {
      print("Intentando enviar mensaje sin conexión activa");
    }
  }

  // 3. DESCONECTAR
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
      print("🔌 WebSocket desconectado");
    }
  }
}
