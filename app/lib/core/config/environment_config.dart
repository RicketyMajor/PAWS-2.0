import 'package:flutter/foundation.dart'; // Necesario para kIsWeb
import 'dart:io'; // Necesario para Platform

class EnvironmentConfig {
  // Detecta automáticamente dónde está corriendo la app
  static String get baseUrl {
    if (kIsWeb) {
      // Para Web (Vercel o localhost navegador)
      return 'http://localhost:8080/api/v1';
      // NOTA: Cuando despliegues a Railway, cambiarás esto por tu URL real
    } else if (Platform.isAndroid) {
      // Para Emulador Android
      return 'http://10.0.2.2:8080/api/v1';
    } else {
      // Para iOS o Desktop nativo
      return 'http://localhost:8080/api/v1';
    }
  }

  static String get wsUrl {
    if (kIsWeb) {
      return 'ws://localhost:8080/api/v1';
    } else if (Platform.isAndroid) {
      return 'ws://10.0.2.2:8080/api/v1';
    } else {
      return 'ws://localhost:8080/api/v1';
    }
  }
}
