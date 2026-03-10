// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

/// NOTE: This repository appears to be outdated or deprecated.
/// Its functionality seems to have been split into more specific repositories
/// like `ChatRepository` (for reporting) and `ReviewsRepository` (for reviews).
class SocialRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// A private helper to get authenticated request options.
  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// Creates a user report.
  /// This is likely replaced by the `reportUser` method in `ChatRepository`.
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
      throw Exception('Error sending report: $e');
    }
  }

  /// Creates a user review.
  /// This is likely replaced by the `createReview` method in `ReviewsRepository`.
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
      throw Exception('Error sending review: $e');
    }
  }
}
