import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/report_model.dart';

class AdminRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Obtener lista de reportes pendientes
  Future<List<Report>> getReports() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        // CORRECCIÓN: Concatenamos la URL base
        '${ApiConstants.baseUrl}${ApiConstants.adminReports}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return (response.data as List)
          .map((json) => Report.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando reportes: $e');
    }
  }

  // Obtener detalle con evidencia
  Future<Report> getReportDetails(int id) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        // CORRECCIÓN: Concatenamos la URL base
        '${ApiConstants.baseUrl}${ApiConstants.adminReports}/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      // El backend devuelve { "report": {...}, "evidence": [...] }
      // Nuestro Report.fromJson maneja esta estructura combinada
      return Report.fromJson(response.data);
    } catch (e) {
      throw Exception('Error cargando detalle: $e');
    }
  }

  // Resolver reporte (Banear o Desestimar)
  Future<void> resolveReport(
    int id,
    String action,
    bool publicBlacklist,
  ) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      await _dio.post(
        // CORRECCIÓN: Concatenamos la URL base
        '${ApiConstants.baseUrl}${ApiConstants.adminResolve}/$id/resolve',
        data: {
          'action': action, // 'ban' o 'dismiss'
          'public_blacklist': publicBlacklist,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error resolviendo reporte: $e');
    }
  }
}
