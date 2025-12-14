import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/pet_model.dart';

class PetsRepository {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  Future<List<Pet>> getPets() async {
    try {
      // Llamamos al endpoint público de mascotas
      final response = await _dio.get('${ApiConstants.baseUrl}/pets');

      if (response.statusCode == 200) {
        // La respuesta de Go suele ser { "data": [...] } o directamente [...]
        // Ajustamos según tu estructura. Asumiremos que viene una lista directa o dentro de 'pets'

        // Si tu backend responde: [{"ID":1...}, {"ID":2...}]
        List<dynamic> data = response.data;

        // Mapeamos cada item del JSON a un objeto Pet
        return data.map((json) => Pet.fromJson(json)).toList();
      } else {
        throw Exception('Error al cargar mascotas');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }
}
