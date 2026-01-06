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

  // --- LOGIN (Actualizado para futuro soporte de "Remember Me") ---
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

      // Si "Recuérdame" es true, guardamos en SecureStorage (Persistente)
      // Si es false, idealmente lo guardaríamos solo en memoria, pero por ahora
      // mantenemos el comportamiento estándar para no romper el Bloc.
      await _storage.write(key: 'jwt_token', value: token);

      print('Login exitoso.');
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Error desconocido');
      } else {
        throw Exception('Error de conexión con el servidor');
      }
    }
  }

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
        throw Exception(
          e.response?.data['error'] ?? 'Error de validación en el servidor',
        );
      } else {
        throw Exception('Error de conexión con el servidor');
      }
    }
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
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
          await _storage.write(key: 'jwt_token', value: token);
          return token.toString();
        }
      }
      return null;
    } on DioException {
      return null;
    }
  }

  // ===============================================================
  //  RECUPERACIÓN DE CONTRASEÑA (NUEVO)
  // ===============================================================

  // Paso 1: Solicitar código
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

  // Paso 2: Verificar código
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

  // Paso 3: Cambiar contraseña
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
