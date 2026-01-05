import 'dart:io';
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

  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ===============================================================
  //  LECTURA (ADOPTANTE)
  // ===============================================================

  // En pets_repository.dart

  // En getSwipeDeck, agrega los parámetros opcionales
  Future<List<Pet>> getSwipeDeck({double? lat, double? lon}) async {
    try {
      final options = await _getAuthOptions();

      // Enviamos lat y lon como query parameters
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.swipeDeck}',
        queryParameters: {
          if (lat != null) 'lat': lat,
          if (lon != null) 'lon': lon,
        },
        options: options,
      );

      if (response.statusCode == 200) {
        List<dynamic> data = response.data ?? []; // Protección contra null
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

  // --- NUEVO CREATE PET (Multipart) ---
  Future<void> createPet({
    required String name,
    required String type,
    required String breed,
    required int age,
    required String description,
    required double latitude,
    required double longitude,
    required List<File> images, // <--- LISTA DE FOTOS
    // Salud
    bool isVaccinated = false,
    bool isSterilized = false,
    bool isDewormed = false,
    String specialNeeds = '',

    // Preferencias
    bool requiresYard = false,
    bool goodWithKids = false,
    bool goodWithDogs = false,
    String energyLevel = 'medium',
  }) async {
    try {
      final options = await _getAuthOptions();

      // Construimos el FormData
      final formData = FormData.fromMap({
        "name": name,
        "type": type,
        "breed": breed,
        "age": age,
        "description": description,
        "latitude": latitude,
        "longitude": longitude,

        // Booleans como strings para form-data
        "is_vaccinated": isVaccinated,
        "is_sterilized": isSterilized,
        "is_dewormed": isDewormed,
        "special_needs": specialNeeds,

        "requires_yard": requiresYard,
        "good_with_kids": goodWithKids,
        "good_with_dogs": goodWithDogs,
        "energy_level": energyLevel,
      });

      // Adjuntar imágenes
      for (var file in images) {
        String fileName = file.path.split('/').last;
        formData.files.add(
          MapEntry(
            "images", // Debe coincidir con formMultipart.File["images"] en Go
            await MultipartFile.fromFile(file.path, filename: fileName),
          ),
        );
      }

      await _dio.post(
        '${ApiConstants.baseUrl}/pets',
        data: formData,
        options: options,
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
