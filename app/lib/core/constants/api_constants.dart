class ApiConstants {
  // CAMBIA ESTO por la IP de tu PC donde corre Docker/Kubernetes
  // Si usas emulador Android standard: 10.0.2.2
  // Si usas dispositivo real: Tu IP local (ej: 192.168.1.15)
  static const String baseUrl = 'http://10.0.2.2:8080/api/v1';
  static const String wsUrl = 'ws://10.0.2.2:8080/api/v1';

  // Endpoints Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verifyOtp = '/auth/otp/verify'; // <--- NUEVO

  // Endpoints Match
  static const String swipeDeck = '/matches/candidates';
  static const String swipeAction = '/matches/swipe';
}
