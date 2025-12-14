import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class ChatRepository {
  WebSocketChannel? _channel;
  final _storage = const FlutterSecureStorage();

  // Conectar al WebSocket
  Future<Stream<dynamic>> connect() async {
    // 1. Recuperar el token guardado
    final token = await _storage.read(key: 'jwt_token');

    if (token == null) {
      throw Exception("No hay token para el chat");
    }

    // 2. Armar la URL (ws://IP:8080/api/v1/chat/ws?token=XYZ)
    final uri = Uri.parse('${ApiConstants.wsUrl}?token=$token');

    print("🔌 Conectando al chat: $uri");

    // 3. Abrir conexión
    _channel = WebSocketChannel.connect(uri);

    // 4. Retornar el flujo de datos (Stream) para que el BLoC lo escuche
    return _channel!.stream;
  }

  // Enviar mensaje
  void sendMessage(String message) {
    if (_channel != null) {
      _channel!.sink.add(message);
    }
  }

  // Cerrar conexión
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
  }
}
