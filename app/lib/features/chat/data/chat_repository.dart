import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/api_constants.dart';
import '../../auth/data/auth_repository.dart';

class ChatRepository {
  WebSocketChannel? _channel;
  final AuthRepository authRepository;
  final Dio _dio = Dio();

  final _messageController = StreamController<dynamic>.broadcast();

  ChatRepository({required this.authRepository});

  Stream<dynamic> get messages => _messageController.stream;

  Future<void> connect() async {
    if (_channel != null)
      return; // Evita conectarse dos veces si ya está activo

    final token = await authRepository.getToken();
    if (token == null) throw Exception('No authentication token found');

    final uri = Uri.parse('${ApiConstants.wsUrl}/ws?token=$token');
    _channel = WebSocketChannel.connect(uri);

    // Redirigimos todo lo que llega del servidor a nuestra "Radio Pública"
    _channel!.stream.listen(
      (data) => _messageController.add(data),
      onError: (error) => print("WS Global Error: $error"),
      onDone: () {
        _channel = null; // Si se corta, limpiamos el canal
      },
    );
  }

  Future<List<dynamic>> getHistory(int matchId) async {
    final token = await authRepository.getToken();
    final response = await _dio.get(
      '${ApiConstants.baseUrl}/matches/$matchId/messages',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data;
  }

  void sendMessage(int matchID, String content) {
    if (_channel != null) {
      final message = jsonEncode({"match_id": matchID, "content": content});
      _channel!.sink.add(message);
    }
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
  }

  Future<void> reportUser({
    required int reportedId,
    required int matchId,
    required String category,
    required String description,
  }) async {
    final token = await authRepository.getToken();
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
  }

  // --- MARCAR LEÍDO (Actualizado con AuthRepository) ---
  Future<void> markAsRead(int matchId) async {
    try {
      // Pedimos el token al jefe (AuthRepository)
      final token = await authRepository.getToken();
      if (token == null) throw Exception('Sesión expirada');

      await _dio.post(
        '${ApiConstants.baseUrl}/matches/$matchId/read', // Asegúrate de que esta ruta coincida con tu backend
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error marcando como leído: $e');
    }
  }
}
