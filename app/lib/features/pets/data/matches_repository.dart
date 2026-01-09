import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/match_model.dart'; // Importamos el nuevo modelo

class MatchesRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Obtener solicitudes pendientes (Rescatista)
  Future<List<Match>> getPendingRequests() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/requests',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      // Convertimos la lista dinámica a List<Match>
      return (response.data as List)
          .map((json) => Match.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando solicitudes: $e');
    }
  }

  Future<void> respondMatch(int matchId, bool accept) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      await _dio.post(
        '${ApiConstants.baseUrl}/matches/respond',
        data: {'match_id': matchId, 'accept': accept},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error respondiendo solicitud: $e');
    }
  }

  Future<void> unmatch(int matchId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      await _dio.post(
        '${ApiConstants.baseUrl}/matches/unmatch',
        data: {'match_id': matchId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error saliendo del chat: $e');
    }
  }

  // Obtener chats activos del Rescatista (Ahora retorna List<Match>)
  Future<List<Match>> getRescuerChats() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/rescuer',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (response.data as List)
          .map((json) => Match.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando chats: $e');
    }
  }

  // Obtener matches del Adoptante (Ahora retorna List<Match>)
  Future<List<Match>> getMyPendingMatches() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      // NOTA: Asegúrate que el endpoint en backend para adoptantes (ej: /matches/adopter)
      // devuelva la estructura completa de Match. Si usas uno que solo devuelve Pets, habrá que ajustarlo.
      // Asumiendo que usas /matches/adopter o similar que devuelve Matches:
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/adopter',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (response.data as List)
          .map((json) => Match.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando matches: $e');
    }
  }
}
