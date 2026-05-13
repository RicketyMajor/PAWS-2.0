import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class SocialRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // Enviar Reporte
  Future<void> createReport({
    required int reportedId,
    required String reason,
  }) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/report',
        data: {'reported_id': reportedId, 'reason': reason},
        options: options,
      );
    } catch (e) {
      throw Exception('Error enviando reporte: $e');
    }
  }

  // Enviar Reseña (Rating 1-5)
  Future<void> createReview({
    required int matchId,
    required int rating,
    required String comment,
  }) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/reviews',
        data: {'match_id': matchId, 'rating': rating, 'comment': comment},
        options: options,
      );
    } catch (e) {
      throw Exception('Error enviando reseña: $e');
    }
  }
}
