import 'package:flutter/material.dart';
import '../../constants/api_constants.dart';

class SmartImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SmartImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Si es nulo o vacío, mostramos un placeholder
    if (url == null || url!.isEmpty) {
      return _buildPlaceholder();
    }

    // 2. LÓGICA MAESTRA (Stage 9 Fix)
    // Si la URL ya empieza con "http", es una URL Absoluta (MinIO/S3).
    // Si no, es una ruta relativa antigua y le pegamos el BaseURL.
    final finalUrl = url!.startsWith('http')
        ? url!
        : '${ApiConstants.baseUrl}$url';

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.network(
        finalUrl,
        width: width,
        height: height,
        fit: fit,
        // Manejo de errores de carga (404, server down, etc)
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            width: width,
            height: height,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Icon(
        Icons.pets,
        color: Colors.grey[400],
        size: (width ?? 50) * 0.5,
      ),
    );
  }
}
