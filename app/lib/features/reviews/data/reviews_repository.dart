// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/review_model.dart';
import '../../auth/data/auth_repository.dart';

/// Repository for handling all review-related API requests.
class ReviewsRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository;

  ReviewsRepository({required this.authRepository});

  /// A private helper to get authenticated request options.
  Future<Options> _getAuthOptions() async {
    final token = await authRepository.getToken();
    if (token == null) throw Exception('Session expired or invalid');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// Creates or updates a review for a specific match.
  Future<void> createReview({
    required int matchId,
    required double rating,
    required String comment,
  }) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.reviews}',
        data: {'match_id': matchId, 'rating': rating, 'comment': comment},
        options: options,
      );
    } on DioException catch(e) {
      throw Exception('Error submitting review: ${e.response?.data['error'] ?? e.message}');
    }
  }

  /// Fetches all reviews for a specific user.
  Future<List<Review>> getUserReviews(int userId) async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.userReviews}/$userId/reviews',
        options: options,
      );
      return (response.data as List)
          .map((json) => Review.fromJson(json))
          .toList();
    } on DioException catch(e) {
      throw Exception('Error fetching reviews: ${e.response?.data['error'] ?? e.message}');
    }
  }
}
