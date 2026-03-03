import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart'; // <--- NUEVO IMPORT (Reemplaza a dart:io)
import '../../../core/constants/api_constants.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/user_model.dart';

class UserRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository;

  UserRepository({required this.authRepository});

  Future<Options> _getAuthOptions() async {
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

  Future<User> getUserById(int id) async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/users/$id',
        options: options,
      );
      return User.fromJson(response.data);
    } catch (e) {
      throw Exception('Error obteniendo usuario: $e');
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

  // 3. SUBIR FOTO (AHORA ES MULTIPLATAFORMA)
  Future<String> uploadProfilePicture(XFile file) async {
    // <--- Recibe XFile
    try {
      final options = await _getAuthOptions();
      String fileName = file.name;

      // Transformamos la imagen a Bytes de memoria (100% Soportado por Web y Móvil)
      final bytes = await file.readAsBytes();

      FormData formData = FormData.fromMap({
        "file": MultipartFile.fromBytes(
          bytes,
          filename: fileName,
        ), // <--- fromBytes
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
