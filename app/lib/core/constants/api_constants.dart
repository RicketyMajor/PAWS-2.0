import '../config/environment_config.dart';
import 'package:flutter/foundation.dart';

class ApiConstants {
  static const String baseUrl = kReleaseMode
      ? 'https://paws-20-production.up.railway.app/api/v1' // <--- TU URL DE RAILWAY AQUÍ
      : 'http://10.0.2.2:8080/api/v1';
  static String get wsUrl => EnvironmentConfig.wsUrl;

  // Endpoints Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verifyOtp = '/auth/otp/verify'; // <--- NUEVO

  // Endpoints Match
  static const String swipeDeck = '/matches/candidates';
  static const String swipeAction = '/matches/swipe';
}
