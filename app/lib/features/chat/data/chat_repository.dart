// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/api_constants.dart';
import '../../auth/data/auth_repository.dart';

/// Repository for handling chat-related functionalities, including WebSocket
/// communication and REST API calls for chat history and moderation.
class ChatRepository {
  WebSocketChannel? _channel;
  final AuthRepository authRepository;
  final Dio _dio = Dio();

  // A broadcast stream controller to allow multiple listeners to receive WebSocket messages.
  final _messageController = StreamController<dynamic>.broadcast();

  ChatRepository({required this.authRepository});

  /// A public stream of incoming WebSocket messages.
  Stream<dynamic> get messages => _messageController.stream;

  /// Establishes a WebSocket connection using the user's authentication token.
  Future<void> connect() async {
    if (_channel != null) return; // Avoid reconnecting if already connected.

    final token = await authRepository.getToken();
    if (token == null) throw Exception('No authentication token found');

    final uri = Uri.parse('${ApiConstants.wsUrl}/ws?token=$token');
    _channel = WebSocketChannel.connect(uri);

    // Listen to the WebSocket stream and pipe all data into our broadcast controller.
    _channel!.stream.listen(
      (data) => _messageController.add(data),
      onError: (error) => print("Global WebSocket Error: $error"),
      onDone: () {
        _channel = null; // Clean up the channel on disconnection.
      },
    );
  }

  /// Fetches the chat history for a specific match.
  Future<List<dynamic>> getHistory(int matchId) async {
    final token = await authRepository.getToken();
    final response = await _dio.get(
      '${ApiConstants.baseUrl}/matches/$matchId/messages',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data;
  }

  /// Sends a chat message through the WebSocket connection.
  void sendMessage(int matchID, String content) {
    if (_channel != null) {
      final message = jsonEncode({"match_id": matchID, "content": content});
      _channel!.sink.add(message);
    }
  }

  /// Disconnects from the WebSocket server.
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
  }

  /// Reports a user in the context of a specific match.
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

  /// Marks all messages in a chat as read for the current user.
  Future<void> markAsRead(int matchId) async {
    try {
      final token = await authRepository.getToken();
      if (token == null) throw Exception('Session expired');

      await _dio.post(
        '${ApiConstants.baseUrl}/matches/$matchId/read',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error marking as read: $e');
    }
  }
}
