import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/review_model.dart';

class ReviewsRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Crear o Actualizar Reseña (Upsert)
  Future<void> createReview({
    required int matchId,
    required double rating,
    required String comment,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.reviews}',
        data: {'match_id': matchId, 'rating': rating, 'comment': comment},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error enviando reseña: $e');
    }
  }

  // Obtener reseñas de un usuario específico (Público/Protegido)
  Future<List<Review>> getUserReviews(int userId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.userReviews}/$userId/reviews',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return (response.data as List)
          .map((json) => Review.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando reseñas: $e');
    }
  }
}
