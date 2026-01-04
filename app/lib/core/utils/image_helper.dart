import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants/api_constants.dart';

class ImageHelper {
  /// Corrige la URL para que funcione en Emulador Android y Dispositivos Reales
  static String fixUrl(String url) {
    if (url.isEmpty) return '';

    // 1. Manejo de URLs Absolutas (MinIO, S3, http...)
    if (url.startsWith('http')) {
      // Si estamos en Android Emulador, cambiamos localhost por 10.0.2.2
      if (!kIsWeb && Platform.isAndroid && url.contains('localhost')) {
        return url.replaceFirst('localhost', '10.0.2.2');
      }
      return url;
    }

    // 2. Manejo de URLs Relativas (/uploads/...)
    // TRUCO: Si la baseUrl termina en /api/v1 y la imagen es estática (/uploads),
    // debemos quitar el /api/v1 para que la URL sea válida.
    String baseUrl = ApiConstants.baseUrl;

    // Si la imagen está en /uploads, asumimos que está en la raíz del servidor, no en la API
    if (url.startsWith('/uploads') && baseUrl.endsWith('/api/v1')) {
      baseUrl = baseUrl.replaceAll('/api/v1', '');
    }

    // Quitar slash final si existe para evitar doble slash
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    // Asegurar que url tenga slash inicial
    if (!url.startsWith('/')) {
      url = '/$url';
    }

    return '$baseUrl$url';
  }

  /// Devuelve el Widget de Imagen inteligente (Red o Asset por defecto)
  static Widget getImage(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (url == null || url.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: Icon(
          Icons.pets,
          color: Colors.grey[500],
          size: (width ?? 50) * 0.5,
        ),
      );
    }

    return Image.network(
      fixUrl(url),
      width: width,
      height: height,
      fit: fit,
      // IMPORTANTE: Manejo de errores visual
      errorBuilder: (context, error, stackTrace) {
        // Descomenta esto para ver en consola por qué falla exactamente
        // print("DEBUG IMAGE ERROR ($url): $error");
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: Icon(
            Icons.broken_image,
            color: Colors.grey[400],
            size: (width ?? 30) * 0.5,
          ),
        );
      },
      // Cacheo y Loading
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

  /// Devuelve un ImageProvider (para usar en CircleAvatar, etc)
  /// NOTA: Usar con cuidado, si falla no hay fallback visual automático en CircleAvatar.
  static ImageProvider getProvider(String? url) {
    if (url == null || url.isEmpty) {
      return const AssetImage('assets/images/placeholder.png');
    }
    return NetworkImage(fixUrl(url));
  }
}
