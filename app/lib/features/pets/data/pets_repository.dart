import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/pet_model.dart';

class PetsRepository {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Helper para headers con token
  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // 1. Obtener el Mazo de Cartas (Algoritmo Inteligente Fase 9)
  Future<List<Pet>> getSwipeDeck() async {
    try {
      final options = await _getAuthOptions();
      // Endpoint: /matches/candidates
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.swipeDeck}',
        options: options,
      );

      if (response.statusCode == 200) {
        List<dynamic> data = response.data;
        return data.map((json) => Pet.fromJson(json)).toList();
      }
      return [];
    } on DioException catch (e) {
      // --- INICIO DE LA CORRECCIÓN ---
      String errorMessage = 'Error cargando mascotas';

      if (e.response != null) {
        final data = e.response!.data;

        // Verificamos el tipo de dato antes de leerlo
        if (data is Map<String, dynamic>) {
          // Si es un JSON normal (ej: {"error": "No autorizado"})
          errorMessage = data['error'] ?? errorMessage;
        } else {
          // Si es Texto plano (ej: "panic: interface conversion...")
          // Esto evita el error: type 'String' is not a subtype of type 'int' of 'index'
          errorMessage = data.toString();
        }
      }

      print("ERROR REAL DEL BACKEND: $errorMessage");
      throw Exception(errorMessage);
      // --- FIN DE LA CORRECCIÓN ---
    }
  }

  // 2. Ejecutar Swipe (Like/Dislike)
  Future<void> swipePet({required int petId, required bool isLike}) async {
    try {
      final options = await _getAuthOptions();
      // Endpoint: /matches/swipe
      await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.swipeAction}',
        options: options,
        data: {'pet_id': petId, 'is_like': isLike},
      );
    } catch (e) {
      print("Error en swipe: $e");
      // No lanzamos excepción para no interrumpir la UI fluida
    }
  }
}
