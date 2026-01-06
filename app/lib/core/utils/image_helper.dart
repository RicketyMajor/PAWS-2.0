import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants/api_constants.dart';

class ImageHelper {
  /// Corrige la URL para que funcione en Emulador Android y Dispositivos Reales
  static String fixUrl(String url) {
    if (url.isEmpty) return '';

    String finalUrl = url;

    // 1. Si la URL es relativa (ej: /paws-bucket/...), le falta el dominio.
    // Asumimos que es MinIO (puerto 9000) en el host del emulador.
    if (!url.startsWith('http')) {
      // Asegurar slash inicial
      if (!url.startsWith('/')) {
        finalUrl = '/$url';
      }

      // Si estamos en Android Emulador, forzamos la dirección de MinIO
      if (!kIsWeb && Platform.isAndroid) {
        finalUrl = 'http://10.0.2.2:9000$finalUrl';
      } else {
        // Fallback para iOS u otros (Localhost)
        finalUrl = 'http://localhost:9000$finalUrl';
      }
    }

    // 2. Manejo de URLs Absolutas con localhost
    if (finalUrl.contains('localhost')) {
      if (!kIsWeb && Platform.isAndroid) {
        finalUrl = finalUrl.replaceFirst('localhost', '10.0.2.2');
      }
    }

    // Debug Log (Para que veas en consola qué URL final se está pidiendo)
    // print("IMAGE HELPER: $url -> $finalUrl");
    return finalUrl;
  }

  /// Devuelve el Widget de Imagen inteligente
  static Widget getImage(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (url == null || url.isEmpty) {
      return _buildPlaceholder(width, height);
    }

    return Image.network(
      fixUrl(url),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        print("ERROR CARGANDO IMAGEN (${fixUrl(url)}): $error");
        return _buildErrorPlaceholder(width, height);
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey[100],
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
              strokeWidth: 2,
            ),
          ),
        );
      },
    );
  }

  static ImageProvider getProvider(String? url) {
    if (url == null || url.isEmpty) {
      return const AssetImage(
        'assets/images/placeholder.png',
      ); // Asegúrate de tener este asset o usa un NetworkImage placeholder
    }
    return NetworkImage(fixUrl(url));
  }

  static Widget _buildPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: Icon(Icons.pets, color: Colors.grey[500], size: 40),
    );
  }

  static Widget _buildErrorPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Icon(Icons.broken_image, color: Colors.grey[400], size: 40),
    );
  }
}
