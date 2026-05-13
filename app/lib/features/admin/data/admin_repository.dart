import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/report_model.dart';
import '../../auth/data/auth_repository.dart'; // <--- IMPORTANTE

class AdminRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository; // <--- Inyectamos el jefe de auth

  AdminRepository({
    required this.authRepository,
  }); // <--- Constructor actualizado

  Future<List<Report>> getReports() async {
    try {
      final token = await authRepository.getToken(); // Usamos el método seguro
      final response = await _dio.get(
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

  Future<Report> getReportDetails(int id) async {
    try {
      final token = await authRepository.getToken();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.adminReports}/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return Report.fromJson(response.data);
    } catch (e) {
      throw Exception('Error cargando detalle: $e');
    }
  }

  Future<void> resolveReport(
    int id,
    String action,
    bool publicBlacklist,
  ) async {
    try {
      final token = await authRepository.getToken();
      await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.adminResolve}/$id/resolve',
        data: {'action': action, 'public_blacklist': publicBlacklist},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error resolviendo reporte: $e');
    }
  }
}
