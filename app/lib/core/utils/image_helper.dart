import 'package:flutter/material.dart';

class ImageHelper {
  /// Filtra y valida la URL. Si pertenece al servidor local antiguo (MinIO)
  /// o está incompleta, devuelve un string vacío para forzar el Placeholder.
  static String fixUrl(String url) {
    if (url.isEmpty) return '';

    // Si la URL apunta al servidor antiguo de MinIO o es una ruta relativa vieja
    if (url.contains('10.0.2.2:9000') ||
        url.contains('localhost:9000') ||
        !url.startsWith('http')) {
      return '';
    }

    return url;
  }

  /// Devuelve el Widget de Imagen inteligente
  static Widget getImage(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    final safeUrl = fixUrl(url ?? '');

    // Si la URL fue invalidada por el fixUrl, mostramos el placeholder directamente
    if (safeUrl.isEmpty) {
      return _buildPlaceholder(width, height);
    }

    return Image.network(
      safeUrl,
      width: width,
      height: height,
      fit: fit,
      // Si la imagen de Cloudinary llegara a fallar, este constructor la atrapa
      errorBuilder: (context, error, stackTrace) {
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
              color: const Color(0xFFE91E63),
            ),
          ),
        );
      },
    );
  }

  /// Provee la imagen para widgets como CircleAvatar
  static ImageProvider getProvider(String? url) {
    final safeUrl = fixUrl(url ?? '');

    if (safeUrl.isEmpty) {
      // Retornamos una imagen transparente o un asset por defecto
      // (Asegúrate de tener un asset en esta ruta, o simplemente deja que el
      // CircleAvatar maneje el color de fondo usando null en backgroundImage)
      return const AssetImage('assets/images/placeholder.png');
    }
    return NetworkImage(safeUrl);
  }

  static Widget _buildPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Icon(Icons.pets, color: Colors.grey[400], size: 40),
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
