// Package widgets contains reusable UI components.
import 'package:flutter/material.dart';
import '../../constants/api_constants.dart';

/// A widget that intelligently displays a network image with fallbacks.
///
/// It handles null/empty URLs, relative paths (by prepending the base API URL),
/// and provides loading and error placeholders.
///
/// NOTE: This widget has overlapping functionality with the `ImageHelper` class.
/// Consider consolidating the logic to a single place to avoid duplication.
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
    // 1. If the URL is null or empty, show a placeholder.
    if (url == null || url!.isEmpty) {
      return _buildPlaceholder();
    }

    // 2. Determine the final URL.
    // If the URL already starts with "http", it's an absolute URL (e.g., from Cloudinary/S3).
    // Otherwise, it's a relative path, and we prepend the API base URL.
    final finalUrl = url!.startsWith('http')
        ? url!
        : '${ApiConstants.baseUrl}$url';

    // Use ClipRRect to apply a border radius if one is provided.
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.network(
        finalUrl,
        width: width,
        height: height,
        fit: fit,
        // Show a placeholder if the image fails to load (e.g., 404, server down).
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        // Show a loading indicator while the image is being fetched.
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

  /// Builds a standard placeholder widget.
  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: borderRadius,
      ),
      child: Icon(
        Icons.pets,
        color: Colors.grey[400],
        size: (width ?? 50) * 0.5,
      ),
    );
  }
}
