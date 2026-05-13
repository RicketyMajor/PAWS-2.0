import 'package:flutter/foundation.dart'; // Usamos foundation en lugar de dart:io

class EnvironmentConfig {
  // TU NUEVA URL DE RENDER
  static const String _renderUrl =
      'https://paws-backend-g9sh.onrender.com/api/v1';
  static const String _renderWsUrl =
      'wss://paws-backend-g9sh.onrender.com/api/v1';

  // Detecta automáticamente dónde está corriendo la app de forma segura para Web
  static String get baseUrl {
    if (kIsWeb) {
      return _renderUrl;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return _renderUrl;
    } else {
      return _renderUrl;
    }
  }

  static String get wsUrl {
    if (kIsWeb) {
      return _renderWsUrl;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return _renderWsUrl;
    } else {
      return _renderWsUrl;
    }
  }
}
