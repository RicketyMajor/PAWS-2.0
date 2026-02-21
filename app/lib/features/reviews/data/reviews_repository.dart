import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/review_model.dart';
import '../../auth/data/auth_repository.dart'; // <--- IMPORTACIÓN CLAVE

class ReviewsRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository;

  ReviewsRepository({required this.authRepository});

  Future<Options> _getAuthOptions() async {
    final token = await authRepository.getToken();
    if (token == null) throw Exception('Sesión expirada o inválida');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<void> createReview({
    required int matchId,
    required double rating,
    required String comment,
  }) async {
    final options = await _getAuthOptions();
    await _dio.post(
      '${ApiConstants.baseUrl}${ApiConstants.reviews}',
      data: {'match_id': matchId, 'rating': rating, 'comment': comment},
      options: options,
    );
  }

  Future<List<Review>> getUserReviews(int userId) async {
    final options = await _getAuthOptions();
    final response = await _dio.get(
      '${ApiConstants.baseUrl}${ApiConstants.userReviews}/$userId/reviews',
      options: options,
    );
    return (response.data as List)
        .map((json) => Review.fromJson(json))
        .toList();
  }
}
