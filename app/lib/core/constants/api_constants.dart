import '../config/environment_config.dart';
import 'package:flutter/foundation.dart';

class ApiConstants {
  static const String baseUrl = kReleaseMode
      ? 'https://paws-20-production.up.railway.app/api/v1'
      : 'http://10.0.2.2:8080/api/v1';
  static String get wsUrl => EnvironmentConfig.wsUrl;

  // Endpoints Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verifyOtp = '/auth/otp/verify';

  // Endpoints Match
  static const String swipeDeck = '/matches/candidates';
  static const String swipeAction = '/matches/swipe';
  static const String pendingRequests = '/matches/requests';

  // Endpoints Reportes (Usuario)
  static const String reportUser = '/report';

  // --- ENDPOINTS RESEÑAS (NUEVO) ---
  static const String reviews = '/reviews'; // POST (Crear/Editar)
  static const String userReviews = '/users'; // GET /users/:id/reviews

  // Endpoints Admin
  static const String adminReports = '/admin/reports';
  static const String adminResolve = '/admin/reports';
  static const String blacklistSearch = '/blacklist/search';
}
