import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../../auth/data/auth_repository.dart'; // Importar AuthRepository

class UserRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository; // Dependencia

  UserRepository({required this.authRepository});

  Future<Options> _getAuthOptions() async {
    // Pedimos el token al repositorio central (maneja RAM y Disco por nosotros)
    final token = await authRepository.getToken();
    if (token == null) throw Exception('No hay sesión activa');
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

  // 2. ACTUALIZAR PERFIL
  Future<void> updateProfile({
    required String name,
    required String bio,
    required String phone,
    required String photoUrl,
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
      // Usamos try-catch silencioso porque getToken puede ser null si no hay sesión
      final token = await authRepository.getToken();
      if (token == null) return;

      await _dio.post(
        '${ApiConstants.baseUrl}/notifications/token',
        data: {'token': fcmToken},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      print("Error guardando token FCM: $e");
    }
  }
}
