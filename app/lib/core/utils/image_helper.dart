// Package utils provides various helper classes and functions.
import 'package:flutter/material.dart';

/// A helper class for displaying network images with fallbacks and URL fixing.
class ImageHelper {
  /// Validates a URL. If it points to an old local server (MinIO) or is
  /// an incomplete relative path, it returns an empty string to force a placeholder.
  static String fixUrl(String url) {
    if (url.isEmpty) return '';

    // If the URL points to the old MinIO server or is an old relative path, invalidate it.
    if (url.contains('10.0.2.2:9000') ||
        url.contains('localhost:9000') ||
        !url.startsWith('http')) {
      return '';
    }
    return url;
  }

  /// Returns an intelligent Image widget that handles loading, errors, and invalid URLs.
  static Widget getImage(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    final safeUrl = fixUrl(url ?? '');

    // If fixUrl invalidated the URL, show the placeholder directly.
    if (safeUrl.isEmpty) {
      return _buildPlaceholder(width, height);
    }

    return Image.network(
      safeUrl,
      width: width,
      height: height,
      fit: fit,
      // If the network image fails to load, show an error placeholder.
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorPlaceholder(width, height);
      },
      // While the image is loading, show a progress indicator.
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

  /// Returns an ImageProvider for use in widgets like CircleAvatar.
  /// Falls back to a default asset if the URL is invalid.
  static ImageProvider getProvider(String? url) {
    final safeUrl = fixUrl(url ?? '');

    if (safeUrl.isEmpty) {
      // NOTE: This asset path 'assets/images/placeholder.png' does not seem to exist.
      // Ensure you have a placeholder image at this path in your pubspec.yaml,
      // or the app may throw an error. A typical path is 'assets/icon/icon.png'.
      return const AssetImage('assets/images/placeholder.png');
    }
    return NetworkImage(safeUrl);
  }

  /// Builds a standard placeholder widget.
  static Widget _buildPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Icon(Icons.pets, color: Colors.grey[400], size: 40),
    );
  }

  /// Builds a placeholder widget for when an image fails to load.
  static Widget _buildErrorPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Icon(Icons.broken_image, color: Colors.grey[400], size: 40),
    );
  }
}
