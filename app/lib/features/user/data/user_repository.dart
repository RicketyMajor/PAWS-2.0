import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class UserRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Options> _getAuthOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // 1. OBTENER PERFIL
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/profile',
        options: options,
      );
      return response.data;
    } catch (e) {
      throw Exception('Error cargando perfil: $e');
    }
  }

  // 2. ACTUALIZAR PERFIL (Expandido)
  Future<void> updateProfile({
    required String name,
    required String bio,
    required String phone,
    required String photoUrl,

    // --- NUEVOS CAMPOS (Vivienda & Estilo de Vida) ---
    String housingType = 'House',
    String housingOwnership = 'Owned',
    bool hasYard = false,
    bool hasFence = false,
    String familyComposition = 'Single',
    String otherPets = 'None',
    String timeAvailability = 'Medium',
    String experience = 'Beginner',
  }) async {
    try {
      final options = await _getAuthOptions();
      await _dio.put(
        '${ApiConstants.baseUrl}/profile',
        options: options,
        data: {
          "name": name,
          "bio": bio,
          "phone": phone,
          "photo_url": photoUrl,

          // Mapeo exacto a los JSON tags de Go
          "housing_type": housingType,
          "housing_ownership": housingOwnership,
          "has_yard": hasYard,
          "has_fence": hasFence,
          "family_composition": familyComposition,
          "other_pets": otherPets,
          "time_availability": timeAvailability,
          "experience": experience,
        },
      );
    } catch (e) {
      throw Exception('Error actualizando perfil: $e');
    }
  }

  // 3. SUBIR FOTO
  Future<String> uploadProfilePicture(File file) async {
    try {
      final options = await _getAuthOptions();
      String fileName = file.path.split('/').last;

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await _dio.post(
        '${ApiConstants.baseUrl}/files/upload',
        data: formData,
        options: options,
      );

      return response.data['url'];
    } catch (e) {
      throw Exception('Error subiendo imagen: $e');
    }
  }

  // 4. GUARDAR TOKEN FCM
  Future<void> saveDeviceToken(String fcmToken) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/notifications/token',
        data: {'token': fcmToken},
        options: options,
      );
    } catch (e) {
      print("Error guardando token FCM: $e");
    }
  }
}
