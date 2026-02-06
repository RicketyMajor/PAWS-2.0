import 'package:flutter/foundation.dart'; // Necesario para kIsWeb
import 'dart:io'; // Necesario para Platform

class EnvironmentConfig {
  // TU NUEVA URL DE RENDER
  static const String _renderUrl =
      'https://paws-backend-g9sh.onrender.com/api/v1';
  static const String _renderWsUrl =
      'wss://paws-backend-g9sh.onrender.com/api/v1';

  // Detecta automáticamente dónde está corriendo la app
  static String get baseUrl {
    if (kIsWeb) {
      // Para Web (Vercel): Usamos Render
      return _renderUrl;
    } else if (Platform.isAndroid) {
      // Para Emulador Android: Usamos Render para probar la migración real
      // (Antes usabas 'http://10.0.2.2:8080/api/v1' para local)
      return _renderUrl;
    } else {
      // Para iOS o Desktop: Usamos Render
      return _renderUrl;
    }
  }

  static String get wsUrl {
    if (kIsWeb) {
      return _renderWsUrl;
    } else if (Platform.isAndroid) {
      return _renderWsUrl;
    } else {
      return _renderWsUrl;
    }
  }
}
