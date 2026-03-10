// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

/// Repository for handling all authentication-related API requests.
/// It manages tokens, user sessions, and API calls for login, register, etc.
class AuthRepository {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // In-memory token for the current session if "Remember Me" is false.
  String? _sessionToken;

  /// Creates a new AuthRepository and sets up Dio interceptors.
  AuthRepository() {
    // Interceptor for logging requests and responses.
    _dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestBody: true,
        responseBody: true,
        error: true,
      ),
    );

    // Interceptor to automatically inject the JWT token into every request.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options); // Continue with the request.
        },
      ),
    );
  }

  // =========================================================================
  // Session & Login
  // =========================================================================

  /// Attempts to log in a user and handles token persistence.
  Future<void> login(String email, String password, {bool rememberMe = true}) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/login',
        data: {'email': email, 'password': password},
      );
      final token = response.data['token'];

      // Store the token based on the "rememberMe" flag.
      if (rememberMe) {
        await _storage.write(key: 'jwt_token', value: token);
      } else {
        _sessionToken = token; // Store in memory only for the current session.
        await _storage.delete(key: 'jwt_token'); // Ensure no old persistent token remains.
      }
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Unknown error');
      } else {
        throw Exception('Server connection error');
      }
    }
  }

  /// Switches the user's role and updates the token.
  Future<Map<String, dynamic>?> switchRole() async {
    try {
      // The interceptor automatically adds the token.
      final response = await _dio.post('${ApiConstants.baseUrl}/auth/switch-role');

      if (response.statusCode == 200) {
        final newToken = response.data['token'];
        final newUser = response.data['user'];

        // Update the token in the same place it was originally stored.
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
        return null; // Return null if the other role profile doesn't exist.
      }
      throw Exception(e.response?.data['error'] ?? 'Error switching identity');
    }
  }

  /// Retrieves the current token, prioritizing the session token over the stored one.
  Future<String?> getToken() async {
    if (_sessionToken != null) return _sessionToken;
    return await _storage.read(key: 'jwt_token');
  }

  /// Clears the current session token and any persistently stored token.
  Future<void> logout() async {
    _sessionToken = null;
    await _storage.delete(key: 'jwt_token');
  }

  // =========================================================================
  // Registration
  // =========================================================================

  /// Initiates the registration process.
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
        data: {'email': email, 'password': password, 'name': name, 'run': run, 'role': role},
      );
      if (response.statusCode != 201 && response.statusCode != 200) {
        throw Exception('Failed to initiate registration');
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error'] ?? 'Connection error');
    }
  }

  /// Verifies the OTP and completes the registration, returning a new token.
  Future<String?> verifyOtp(String email, String code) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/auth/otp/verify',
        data: {'email': email, 'code': code},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final token = response.data['token'];
        if (token != null) {
          // Assume persistence on successful registration.
          await _storage.write(key: 'jwt_token', value: token);
          return token.toString();
        }
      }
      return null;
    } on DioException {
      return null; // OTP was incorrect.
    }
  }

  // =========================================================================
  // Password Recovery
  // =========================================================================

  /// Sends a password recovery request.
  Future<void> forgotPassword(String email) async {
    try {
      await _dio.post(
        '${ApiConstants.baseUrl}/auth/forgot-password',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['error'] ?? 'Error sending request');
    }
  }

  /// Verifies the password recovery code.
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

  /// Resets the user's password with a new one.
  Future<void> resetPassword(String email, String newPassword) async {
    try {
      await _dio.post(
        '${ApiConstants.baseUrl}/auth/reset-password',
        data: {'email': email, 'new_password': newPassword},
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['error'] ?? 'Error resetting password');
    }
  }
}
