import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class AuthRepository {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Variable en memoria para sesión temporal (si "Recuérdame" es false)
  String? _sessionToken;

  AuthRepository() {
    _dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestBody: true,
        responseBody: true,
        error: true,
      ),
    );
  }

  // --- LOGIN ---
  Future<void> login(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/login',
        data: {'email': email, 'password': password},
      );

      final token = response.data['token'];

      // Lógica de Persistencia
      if (rememberMe) {
        await _storage.write(key: 'jwt_token', value: token);
      } else {
        // Solo en memoria (se borra al cerrar la app)
        _sessionToken = token;
        // Aseguramos que no quede basura de una sesión anterior persistente
        await _storage.delete(key: 'jwt_token');
      }

      print('Login exitoso. Persistencia: $rememberMe');
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Error desconocido');
      } else {
        throw Exception('Error de conexión con el servidor');
      }
    }
  }

  // --- SWITCH ROLE ---
  Future<Map<String, dynamic>?> switchRole() async {
    try {
      final token = await getToken(); // Usamos el getter inteligente
      if (token == null) throw Exception("No hay sesión activa");

      final response = await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.switchRole}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final newToken = response.data['token'];
        final newUser = response.data['user'];

        // Si tenemos token en storage, actualizamos storage.
        // Si tenemos token en memoria, actualizamos memoria.
        final storedToken = await _storage.read(key: 'jwt_token');
        if (storedToken != null) {
          await _storage.write(key: 'jwt_token', value: newToken);
        } else {
          _sessionToken = newToken;
        }

        return newUser;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw Exception(
        e.response?.data['error'] ?? 'Error cambiando de identidad',
      );
    }
  }

  // Modificado para soportar sesión temporal
  Future<String?> getToken() async {
    // 1. Intentar memoria (prioridad sesión actual)
    if (_sessionToken != null) return _sessionToken;
    // 2. Intentar disco (persistencia)
    return await _storage.read(key: 'jwt_token');
  }

  // Nuevo método para Logout
  Future<void> logout() async {
    _sessionToken = null;
    await _storage.delete(key: 'jwt_token');
  }

  // ... (Resto de métodos: register, verifyOtp, forgotPassword, etc. se mantienen IGUAL) ...
  // COPIA AQUÍ EL RESTO DE TUS MÉTODOS EXISTENTES (register, verifyOtp, etc) SIN CAMBIOS

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String run,
    String role = 'adopter',
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/register',
        data: {
          'email': email,
          'password': password,
          'name': name,
          'run': run,
          'role': role,
        },
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        print('Registro exitoso');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Error de validación');
      } else {
        throw Exception('Error de conexión');
      }
    }
  }

  Future<String?> verifyOtp(String email, String code) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/otp/verify',
        data: {'email': email, 'code': code},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final token = response.data['token'];
        if (token != null) {
          // Por defecto en registro asumimos persistencia true
          await _storage.write(key: 'jwt_token', value: token);
          return token.toString();
        }
      }
      return null;
    } on DioException {
      return null;
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await _dio.post(
        '${ApiConstants.baseUrl}/auth/forgot-password',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['error'] ?? 'Error enviando solicitud');
    }
  }

  Future<bool> verifyRecoveryCode(String email, String code) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/verify-recovery',
        data: {'email': email, 'code': code},
      );
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  Future<void> resetPassword(String email, String newPassword) async {
    try {
      await _dio.post(
        '${ApiConstants.baseUrl}/auth/reset-password',
        data: {'email': email, 'new_password': newPassword},
      );
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['error'] ?? 'Error restableciendo contraseña',
      );
    }
  }
}
