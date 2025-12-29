import 'dart:io'; // <--- IMPORTANTE: Necesario para manejar File
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

  // ===============================================================
  //  LECTURA (ADOPTANTE)
  // ===============================================================

  // En pets_repository.dart

  Future<List<Pet>> getSwipeDeck() async {
    try {
      final options = await _getAuthOptions();

      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.swipeDeck}',
        options: options,
      );

      if (response.statusCode == 200) {
        // CORRECCIÓN: Si response.data es null, usamos una lista vacía []
        List<dynamic> data = response.data ?? [];

        return data.map((json) => Pet.fromJson(json)).toList();
      }
      return [];
    } on DioException catch (e) {
      _handleError(e);
      return [];
    }
  }

  // 2. Obtener TODAS las mascotas (Para el Dashboard del Rescatista)
  // Nota: Esto llama a /pets (público) o podrías crear /pets/my-pets en backend
  Future<List<Pet>> getPets() async {
    try {
      // Usamos el endpoint público por ahora, que lista disponibles
      final response = await _dio.get('${ApiConstants.baseUrl}/pets');

      if (response.statusCode == 200) {
        List<dynamic> data = response.data;
        return data.map((json) => Pet.fromJson(json)).toList();
      }
      return [];
    } on DioException catch (e) {
      _handleError(e);
      return [];
    }
  }

  // ===============================================================
  //  ESCRITURA (RESCATISTA)
  // ===============================================================

  // 3. Subir Imagen (Para crear mascota)
  Future<String> uploadImage(File file) async {
    try {
      final options = await _getAuthOptions();
      String fileName = file.path.split('/').last;

      // Creamos el FormData para simular un formulario HTML multipart
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await _dio.post(
        '${ApiConstants.baseUrl}/files/upload',
        data: formData,
        options: options,
      );

      if (response.statusCode == 200) {
        // El backend retorna { "url": "/uploads/uuid.jpg", ... }
        return response.data['url'];
      } else {
        throw Exception('Error al subir imagen');
      }
    } on DioException catch (e) {
      _handleError(e);
      return '';
    }
  }

  // 4. Crear Mascota
  Future<void> createPet({
    required String name,
    required String type,
    required String breed,
    required int age,
    required String description,
    required String imageUrl,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final options = await _getAuthOptions();

      // Enviamos el JSON al backend
      await _dio.post(
        '${ApiConstants.baseUrl}/pets',
        options: options,
        data: {
          "name": name,
          "type": type,
          "breed": breed,
          "age": age,
          "description": description,
          // IMPORTANTE: Asegúrate que tu backend Go mapee este campo correctamente
          // Si tu struct Go es `PhotoURL string`, Gin suele esperar `photo_url` o `PhotoURL`
          "photo_url": imageUrl,
          "latitude": latitude,
          "longitude": longitude,
        },
      );
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  // ===============================================================
  //  INTERACCIÓN (MATCHING)
  // ===============================================================

  // 5. Ejecutar Swipe (Like/Dislike)
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

  // Helper de errores centralizado
  void _handleError(DioException e) {
    String errorMessage = 'Error de conexión';

    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map<String, dynamic>) {
        errorMessage = data['error'] ?? errorMessage;
      } else {
        errorMessage = data.toString();
      }
    }

    print("PETS REPO ERROR: $errorMessage");
    throw Exception(errorMessage);
  }

  // ... dentro de PetsRepository ...

  // 6. Eliminar Mascota
  Future<void> deletePet(int id) async {
    try {
      final options = await _getAuthOptions();
      await _dio.delete('${ApiConstants.baseUrl}/pets/$id', options: options);
    } on DioException catch (e) {
      _handleError(e);
    }
  }
}
