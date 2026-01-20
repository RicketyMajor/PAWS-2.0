import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class ChatRepository {
  WebSocketChannel? _channel;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Dio _dio = Dio();

  Stream<dynamic> get messages => _channel?.stream ?? const Stream.empty();

  // 1. CONECTAR WEBSOCKET
  Future<void> connect() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) throw Exception('No authentication token found');

    // WS URL: Ajustar según tu ApiConstants (ws:// o wss://)
    final uri = Uri.parse('${ApiConstants.wsUrl}/ws');

    try {
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
        pingInterval: const Duration(seconds: 10),
      );
      print("Conectado al Chat WS: $uri");
    } catch (e) {
      print("Error conectando WS: $e");
      rethrow;
    }
  }

  // 2. OBTENER HISTORIAL (HTTP)
  Future<List<dynamic>> getHistory(int matchId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/$matchId/messages',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      print("Error cargando historial: $e");
      return [];
    }
  }

  // 3. ENVIAR MENSAJE (WS)
  void sendMessage(int matchID, String content) {
    if (_channel != null) {
      final message = jsonEncode({"match_id": matchID, "content": content});
      _channel!.sink.add(message);
    } else {
      print("Intentando enviar mensaje sin conexión activa");
    }
  }

  // 4. DESCONECTAR
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
      print("WebSocket desconectado");
    }
  }

  // --- NUEVO: REPORTAR USUARIO ---
  Future<void> reportUser({
    required int reportedId,
    required int matchId,
    required String category,
    required String description,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      await _dio.post(
        '${ApiConstants.baseUrl}/report',
        data: {
          'reported_id': reportedId,
          'match_id': matchId,
          'category': category,
          'description': description,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error enviando reporte: $e');
    }
  }
}
