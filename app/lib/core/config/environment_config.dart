// Package config contains environment-specific configurations.
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// EnvironmentConfig provides the base URLs for API and WebSocket connections.
/// It detects the platform to provide the appropriate URL.
class EnvironmentConfig {
  // Production backend URLs hosted on Render.
  static const String _renderApiUrl = 'https://paws-backend-g9sh.onrender.com/api/v1';
  static const String _renderWsUrl = 'wss://paws-backend-g9sh.onrender.com/api/v1';

  /// Returns the appropriate base URL for HTTP API calls.
  ///
  /// Currently, it returns the production Render URL for all platforms.
  /// In a typical setup, this might return a local URL for debug/development builds.
  /// Example: `return 'http://10.0.2.2:8080/api/v1';` for Android emulator.
  static String get baseUrl {
    // This logic is currently configured to always use the production URL.
    if (kIsWeb) {
      return _renderApiUrl;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return _renderApiUrl;
    } else {
      return _renderApiUrl;
    }
  }

  /// Returns the appropriate URL for WebSocket connections.
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
