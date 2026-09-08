import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../../auth/data/auth_repository.dart';

class SecurityRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository;

  SecurityRepository({required this.authRepository});

  // Retorna un Map con el resultado: { "found": bool, "name": String?, "reason": String? }
  Future<Map<String, dynamic>> checkBlacklist(String rut) async {
    final token = await authRepository.getToken();
    if (token == null) throw Exception('Sesión expirada o inválida');

    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.blacklistSearch}',
        queryParameters: {'rut': rut},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      // The route is no longer public, so 401 and 429 are ordinary answers now, and
      // reporting either as a connection error sends the user off to check their wifi
      // when the problem is their session or how fast they are searching.
      switch (e.response?.statusCode) {
        case 401:
          throw Exception('Tu sesión expiró. Vuelve a iniciar sesión.');
        case 429:
          throw Exception('Demasiadas consultas seguidas. Espera un momento.');
      }
      // Never surface the exception itself: it carries the request URL, and this
      // route's URL has the RUN in its query string.
      if (e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Error consultando antecedentes');
      }
      throw Exception('Error de conexión con el servidor');
    }
  }
}
