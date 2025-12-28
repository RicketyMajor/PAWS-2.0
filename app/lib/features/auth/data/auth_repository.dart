import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class AuthRepository {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(
        seconds: 10,
      ), // Falla si no conecta en 5 segs
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  // Almacenamiento seguro para el Token (Keychain en iOS, Keystore en Android)
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // --- AGREGA ESTE CONSTRUCTOR ---
  AuthRepository() {
    // Esto imprimirá TODO lo que pasa por la red en tu terminal
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

      // Si llegamos aquí, Go respondió 200 OK
      final token = response.data['token'];

      // Guardamos el token en el celular de forma segura
      await _storage.write(key: 'jwt_token', value: token);

      print('Login exitoso. Token guardado: ${token.substring(0, 10)}...');
    } on DioException catch (e) {
      // Manejamos errores de red o credenciales inválidas
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
    String role = 'adopter', // Por defecto creamos "Adoptantes"
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/register',
        data: {
          'email': email,
          'password': password,
          'name': name,
          'run': run, // <--- Agregamos el RUN
          'role': role, // <--- Agregamos el Rol
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('Registro exitoso');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        // Esto captura el error rojo que viste y lo lanza para mostrarlo en el SnackBar
        throw Exception(
          e.response?.data['error'] ?? 'Error de validación en el servidor',
        );
      } else {
        throw Exception('Error de conexión con el servidor');
      }
    }
  }

  // --- AGREGAR ESTA FUNCIÓN (Soluciona el error rojo en LoginScreen) ---
  Future<String?> getToken() async {
    // Lee el token guardado en el almacenamiento seguro
    return await _storage.read(key: 'jwt_token');
  }

  // --- ACTUALIZAR ESTA FUNCIÓN (Para el Auto-Login en OTP) ---
  // Cambiamos Future<bool> por Future<String?>
  Future<String?> verifyOtp(String email, String code) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/otp/verify',
        data: {'email': email, 'code': code},
      );

      if (response.statusCode == 200) {
        // 1. Extraer el token de la respuesta
        final token = response.data['token'];

        // 2. Guardarlo (Login automático)
        if (token != null) {
          await _storage.write(key: 'jwt_token', value: token);
          return token.toString();
        }
      }
      return null;
    } on DioException catch (e) {
      // Manejo de errores silencioso para la UI
      return null;
    }
  }
}
