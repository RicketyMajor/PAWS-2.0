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

  // 1. OBTENER PERFIL ACTUAL
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/profile', // Ruta GET creada en el paso anterior
        options: options,
      );
      return response.data;
    } catch (e) {
      throw Exception('Error cargando perfil: $e');
    }
  }

  // 2. ACTUALIZAR DATOS (Texto)
  Future<void> updateProfile({
    required String name,
    required String bio,
    required String phone,
    required String photoUrl,
  }) async {
    try {
      final options = await _getAuthOptions();
      await _dio.put(
        '${ApiConstants.baseUrl}/profile', // Ruta PUT
        options: options,
        data: {"name": name, "bio": bio, "phone": phone, "photo_url": photoUrl},
      );
    } catch (e) {
      throw Exception('Error actualizando perfil: $e');
    }
  }

  // 3. SUBIR FOTO DE PERFIL
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

      return response.data['url']; // Retorna la URL relativa (/uploads/...)
    } catch (e) {
      throw Exception('Error subiendo imagen: $e');
    }
  }
}
