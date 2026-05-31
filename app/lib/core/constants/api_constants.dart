import 'package:flutter/foundation.dart';

class ApiConstants {
  // kReleaseMode es 'true' en Vercel y en el APK de Release, pero 'false' en tu emulador
  static const String baseUrl = kReleaseMode
      ? 'https://paws-backend-m2g2.onrender.com/api/v1' // PRODUCCIÓN (Nube)
      : 'http://10.0.2.2:8080/api/v1'; // DESARROLLO (Localhost de tu PC)

  // Aplicamos la misma regla de seguridad para el servidor de WebSockets
  static const String wsUrl = kReleaseMode
      ? 'wss://paws-backend-m2g2.onrender.com/api/v1' // PRODUCCIÓN WS (Secure WebSockets)
      : 'ws://10.0.2.2:8080/api/v1'; // DESARROLLO WS

  // Endpoints Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verifyOtp = '/auth/otp/verify';
  static const String switchRole = '/auth/switch-role';

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
