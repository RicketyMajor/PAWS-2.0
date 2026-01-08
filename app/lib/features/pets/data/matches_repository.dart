import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';

class MatchesRepository {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Obtener solicitudes pendientes (Rescatista)
  Future<List<dynamic>> getPendingRequests() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/requests',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response
          .data; // Devuelve lista de Matches con datos de Adoptante y Mascota
    } catch (e) {
      throw Exception('Error cargando solicitudes: $e');
    }
  }

  // Responder a una solicitud (Aceptar/Rechazar)
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

  // --- NUEVO: Salir del Chat ---
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

  // Obtener chats activos del Rescatista
  Future<List<dynamic>> getRescuerChats() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/rescuer', // La ruta que acabamos de crear
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      throw Exception('Error cargando chats: $e');
    }
  }

  Future<List<dynamic>> getMyPendingMatches() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/mine/pending',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      throw Exception('Error cargando pendientes: $e');
    }
  }
}
