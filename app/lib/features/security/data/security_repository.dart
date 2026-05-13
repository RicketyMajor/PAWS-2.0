import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';

class SecurityRepository {
  final Dio _dio = Dio();

  // Retorna un Map con el resultado: { "found": bool, "name": String?, "reason": String? }
  Future<Map<String, dynamic>> checkBlacklist(String rut) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.blacklistSearch}',
        queryParameters: {'rut': rut},
      );

      return response.data;
    } catch (e) {
      throw Exception('Error consultando antecedentes: $e');
    }
  }
}
