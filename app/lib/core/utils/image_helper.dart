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
  /// [semanticLabel] describes the image to a screen reader. Leave it null when
  /// the image sits next to text that already names it — a labelled thumbnail
  /// beside its own title is read twice, which is worse than silence.
  static Widget getImage(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    String? semanticLabel,
  }) {
    final safeUrl = fixUrl(url ?? '');

    // Si la URL fue invalidada por el fixUrl, mostramos el placeholder directamente
    if (safeUrl.isEmpty) {
      return _buildPlaceholder(width, height, semanticLabel);
    }

    return Image.network(
      safeUrl,
      width: width,
      height: height,
      fit: fit,
      semanticLabel: semanticLabel,
      // Si la imagen de Cloudinary llegara a fallar, este constructor la atrapa
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorPlaceholder(width, height, semanticLabel);
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

  /// Provee la imagen para widgets como CircleAvatar.
  /// Devuelve null cuando no hay foto: CircleAvatar cae en su backgroundColor.
  /// Antes devolvía AssetImage('assets/images/placeholder.png'), un archivo que
  /// no existe y que además no está declarado en pubspec.yaml, así que cada
  /// avatar sin foto lanzaba una excepción de carga.
  static ImageProvider? getProvider(String? url) {
    final safeUrl = fixUrl(url ?? '');

    if (safeUrl.isEmpty) return null;
    return NetworkImage(safeUrl);
  }

  static Widget _buildPlaceholder(
    double? width,
    double? height,
    String? semanticLabel,
  ) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Icon(
        Icons.pets,
        color: Colors.grey[400],
        size: 40,
        semanticLabel: semanticLabel == null ? null : 'Sin foto',
      ),
    );
  }

  static Widget _buildErrorPlaceholder(
    double? width,
    double? height,
    String? semanticLabel,
  ) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Icon(
        Icons.broken_image,
        color: Colors.grey[400],
        size: 40,
        semanticLabel: semanticLabel == null
            ? null
            : 'La foto no se pudo cargar',
      ),
    );
  }
}
