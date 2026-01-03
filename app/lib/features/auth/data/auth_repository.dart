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

  // Función para hacer Login
  Future<void> login(String email, String password) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/login',
        data: {'email': email, 'password': password},
      );

      final token = response.data['token'];
      await _storage.write(key: 'jwt_token', value: token);

      print('Login exitoso. Token guardado: ${token.substring(0, 10)}...');
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

      // Aceptamos 200 y 201
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

  // --- AQUÍ ESTABA EL ERROR ---
  Future<String?> verifyOtp(String email, String code) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/otp/verify',
        data: {'email': email, 'code': code},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final token = response.data['token'];

        if (token != null) {
          // Guardamos el token para Auto-Login
          await _storage.write(key: 'jwt_token', value: token);
          return token.toString();
        }
      }
      return null;
    } on DioException catch (e) {
      // Si el código es realmente incorrecto (401), caerá aquí y retornará null
      return null;
    }
  }
}
