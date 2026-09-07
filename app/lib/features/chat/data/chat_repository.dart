import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/api_constants.dart';
import '../../auth/data/auth_repository.dart';

/// Marca el token dentro de Sec-WebSocket-Protocol. Debe coincidir con
/// wsAuthSubprotocol en el backend.
const String _wsAuthSubprotocol = 'bearer';

const Duration _firstRetryDelay = Duration(seconds: 1);
const Duration _maxRetryDelay = Duration(seconds: 30);

class ChatRepository {
  WebSocketChannel? _channel;
  final AuthRepository authRepository;
  final Dio _dio = Dio();

  // El controller es broadcast y vive tanto como el repositorio, así que sobrevive
  // a las reconexiones: quien esté suscrito no se entera de que el socket cambió.
  final _messageController = StreamController<dynamic>.broadcast();

  Timer? _reconnectTimer;
  int _retryAttempt = 0;
  bool _closedByUser = false;
  // Durante el handshake _channel sigue siendo null. Sin esta bandera, las dos
  // llamadas a connect() (main_layout y chat_bloc) abrirían dos sockets.
  bool _connecting = false;

  ChatRepository({required this.authRepository});

  Stream<dynamic> get messages => _messageController.stream;

  bool get isConnected => _channel != null;

  /// Abre el canal y lo mantiene abierto. Un fallo de red no propaga excepción:
  /// programa un reintento, porque el historial ya se cargó por HTTP y la pantalla
  /// debe seguir siendo utilizable mientras el socket vuelve.
  Future<void> connect() async {
    if (_channel != null || _connecting || _reconnectTimer != null) return;
    _closedByUser = false;
    await _openChannel();
  }

  Future<void> _openChannel() async {
    if (_connecting) return;
    _connecting = true;
    try {
      final token = await authRepository.getToken();
      if (token == null) {
        // Sin sesión no hay nada que reintentar: un fallo de red se reintenta,
        // la ausencia de credenciales no.
        disconnect();
        return;
      }

      // El token viaja en el subprotocolo, no en la URL: Gin registra la ruta con su
      // query string, así que un token ahí acaba escrito en los logs del servidor.
      final channel = WebSocketChannel.connect(
        Uri.parse('${ApiConstants.wsUrl}/ws'),
        protocols: [_wsAuthSubprotocol, token],
      );
      await channel.ready;

      _channel = channel;
      _retryAttempt = 0;

      channel.stream.listen(
        _messageController.add,
        onError: (_) => _handleDrop(),
        onDone: _handleDrop,
        cancelOnError: true,
      );
    } catch (_) {
      _channel = null;
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleDrop() {
    _channel = null;
    if (_closedByUser) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closedByUser || _reconnectTimer != null) return;

    // Backoff exponencial con techo de 30 s. El techo importa: cuando Render
    // despierta de una suspensión tarda cerca de un minuto, y esperar más solo
    // alarga el tiempo que el chat pasa muerto.
    final millis = _firstRetryDelay.inMilliseconds * (1 << _retryAttempt);
    final delay = millis >= _maxRetryDelay.inMilliseconds
        ? _maxRetryDelay
        : Duration(milliseconds: millis);
    // Se detiene en cuanto el retardo alcanza el techo. Dejarlo crecer desbordaría
    // el desplazamiento en Dart web y devolvería retardos de 0.
    if (delay < _maxRetryDelay) _retryAttempt++;

    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_closedByUser) return;
      // _openChannel no propaga: los fallos de red reprograman, la falta de
      // sesión cierra. El catch es una red de seguridad ante lo inesperado.
      try {
        await _openChannel();
      } catch (_) {
        disconnect();
      }
    });
  }

  Future<List<dynamic>> getHistory(int matchId) async {
    final token = await authRepository.getToken();
    final response = await _dio.get(
      '${ApiConstants.baseUrl}/matches/$matchId/messages',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data;
  }

  /// Lanza si no hay canal vivo. Antes descartaba el mensaje en silencio: el usuario
  /// creía haber escrito al rescatista y no se había enviado nada.
  void sendMessage(int matchID, String content) {
    final channel = _channel;
    if (channel == null) {
      throw Exception('Sin conexión con el chat. Reintentando…');
    }
    channel.sink.add(jsonEncode({"match_id": matchID, "content": content}));
  }

  void disconnect() {
    _closedByUser = true;
    _connecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _retryAttempt = 0;
    _channel?.sink.close();
    _channel = null;
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
