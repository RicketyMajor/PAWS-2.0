import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart'; // Para IOWebSocketChannel
import '../../../core/constants/api_constants.dart';
import '../domain/message_model.dart';
import 'package:jwt_decoder/jwt_decoder.dart'; // Útil para sacar el ID del token

class ChatRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  WebSocketChannel? _channel;

  // Obtener mi ID desde el token guardado
  Future<int> _getMyUserId() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return 0;
    Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
    // Asegúrate de que tu backend ponga 'user_id' o 'sub' en el token.
    // Si usas el standard JWT de Go, suele ser 'user_id' o convertir 'sub'.
    return int.tryParse(
          decodedToken['sub'] ?? decodedToken['user_id'].toString(),
        ) ??
        0;
  }

  // 1. Cargar Historial (HTTP)
  Future<List<ChatMessage>> getHistory(int matchId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final myId = await _getMyUserId();

      final response = await _dio.get(
        // URL: /matches/:id/messages
        '${ApiConstants.baseUrl}/matches/$matchId/messages',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        List<dynamic> data = response.data;
        return data.map((json) => ChatMessage.fromJson(json, myId)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Error cargando historial: $e');
    }
  }

  // 2. Conectar WebSocket
  Future<Stream<dynamic>> connectToChat() async {
    final token = await _storage.read(key: 'jwt_token');

    // URL: ws://192.168.x.x:8080/api/v1/ws
    // Importante: Pasamos token en Headers para handshake inicial
    final uri = Uri.parse(ApiConstants.wsUrl);

    _channel = IOWebSocketChannel.connect(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    return _channel!.stream;
  }

  // 3. Enviar Mensaje (WebSocket)
  void sendMessage(int matchId, String content) {
    if (_channel != null) {
      final messageJson = jsonEncode({'match_id': matchId, 'content': content});
      _channel!.sink.add(messageJson);
    }
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
