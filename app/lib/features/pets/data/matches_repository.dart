import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/match_model.dart';
import '../../auth/data/auth_repository.dart'; // Importamos al "Dueño del Token"

class MatchesRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository; // Dependencia inyectada

  // Constructor que exige el AuthRepository
  MatchesRepository({required this.authRepository});

  // Helper privado para obtener cabeceras con el token válido (sea de memoria o disco)
  Future<Options> _getAuthOptions() async {
    final token = await authRepository.getToken();
    if (token == null) throw Exception('Sesión expirada o inválida');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // Obtener solicitudes pendientes (Rescatista)
  Future<List<Match>> getPendingRequests() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/requests',
        options: options,
      );

      return (response.data as List)
          .map((json) => Match.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando solicitudes: $e');
    }
  }

  Future<void> respondMatch(int matchId, bool accept) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/matches/respond',
        data: {'match_id': matchId, 'accept': accept},
        options: options,
      );
    } catch (e) {
      throw Exception('Error respondiendo solicitud: $e');
    }
  }

  Future<void> unmatch(int matchId) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/matches/unmatch',
        data: {'match_id': matchId},
        options: options,
      );
    } catch (e) {
      throw Exception('Error saliendo del chat: $e');
    }
  }

  // Obtener chats activos del Rescatista
  Future<List<Match>> getRescuerChats() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/rescuer',
        options: options,
      );
      return (response.data as List)
          .map((json) => Match.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando chats: $e');
    }
  }

  // Obtener matches del Adoptante
  Future<List<Match>> getMyPendingMatches() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/adopter',
        options: options,
      );
      return (response.data as List)
          .map((json) => Match.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando matches: $e');
    }
  }
}
