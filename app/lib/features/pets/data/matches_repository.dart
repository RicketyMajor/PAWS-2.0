// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/match_model.dart';
import '../../auth/data/auth_repository.dart';

/// Repository for handling all match-related API requests.
class MatchesRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository;

  /// Creates a new MatchesRepository.
  /// Requires an [AuthRepository] for handling authentication tokens.
  MatchesRepository({required this.authRepository});

  /// A private helper to get authenticated request options.
  Future<Options> _getAuthOptions() async {
    final token = await authRepository.getToken();
    if (token == null) throw Exception('Session expired or invalid');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// Fetches pending match requests for the current user (as a rescuer).
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
      throw Exception('Error loading requests: $e');
    }
  }

  /// Responds to a match request (accept or reject).
  Future<void> respondMatch(int matchId, bool accept) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/matches/respond',
        data: {'match_id': matchId, 'accept': accept},
        options: options,
      );
    } catch (e) {
      throw Exception('Error responding to request: $e');
    }
  }

  /// Unmatches from a chat.
  Future<void> unmatch(int matchId) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}/matches/unmatch',
        data: {'match_id': matchId},
        options: options,
      );
    } catch (e) {
      throw Exception('Error leaving chat: $e');
    }
  }

  /// Fetches active chats for the current user (as a rescuer).
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
      throw Exception('Error loading chats: $e');
    }
  }

  /// Fetches accepted matches for the current user (as an adopter).
  Future<List<Match>> getAdopterAcceptedMatches() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/adopter?status=accepted',
        options: options,
      );
      return (response.data as List)
          .map((json) => Match.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error loading active chats: $e');
    }
  }

  /// Fetches pending matches initiated by the current user (as an adopter).
  Future<List<Match>> getAdopterPendingMatches() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/matches/adopter?status=pending',
        options: options,
      );
      return (response.data as List)
          .map((json) => Match.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error loading pending requests: $e');
    }
  }
}
