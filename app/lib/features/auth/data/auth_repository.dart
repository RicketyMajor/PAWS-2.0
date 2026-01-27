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

  // --- SWITCH ROLE (NUEVO) ---
  // Retorna el objeto User (Map) si el cambio fue exitoso.
  // Retorna NULL si la cuenta no existe (404).
  Future<Map<String, dynamic>?> switchRole() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.switchRole}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final newToken = response.data['token'];
        final newUser = response.data['user'];

        // Guardamos el nuevo token inmediatamente
        await _storage.write(key: 'jwt_token', value: newToken);

        return newUser;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null; // Cuenta no existe
      }
      throw Exception(
        e.response?.data['error'] ?? 'Error cambiando de identidad',
      );
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
        throw Exception(e.response?.data['error'] ?? 'Error de validación');
      } else {
        throw Exception('Error de conexión');
      }
    }
  }

  Future<String?> getToken() async => await _storage.read(key: 'jwt_token');

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

  // --- Recuperación de Contraseña ---
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
