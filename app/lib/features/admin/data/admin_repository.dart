import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class AdminRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // Obtener lista de reportes
  Future<List<dynamic>> getReports() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/admin/reports',
        options: options,
      );
      return response.data;
    } catch (e) {
      throw Exception('Error cargando reportes: $e');
    }
  }

  // Banear usuario (El Martillo)
  Future<void> banUser(int userId, String reason) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/admin/ban/$userId',
        data: {'reason': reason},
        options: options,
      );
    } catch (e) {
      throw Exception('Error baneando usuario: $e');
    }
  }
}
