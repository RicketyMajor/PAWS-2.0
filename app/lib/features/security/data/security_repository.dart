// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';

/// Repository for handling security-related API requests, such as checking the public blacklist.
class SecurityRepository {
  final Dio _dio = Dio();

  /// Checks the public blacklist for a given national ID (RUT).
  ///
  /// Returns a Map with the result, e.g.,
  /// `{"found": bool, "name": String?, "reason": String?}`.
  Future<Map<String, dynamic>> checkBlacklist(String rut) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.blacklistSearch}',
        queryParameters: {'rut': rut},
      );
      return response.data;
    } catch (e) {
      throw Exception('Error checking blacklist: $e');
    }
  }
}
