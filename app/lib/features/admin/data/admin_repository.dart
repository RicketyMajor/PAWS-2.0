// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/report_model.dart';
import '../../auth/data/auth_repository.dart';

/// Repository for handling admin-related API requests.
class AdminRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository;

  /// Creates a new AdminRepository.
  ///
  /// Requires an [AuthRepository] to be injected for token management.
  AdminRepository({
    required this.authRepository,
  });

  /// Fetches a list of pending reports from the API.
  Future<List<Report>> getReports() async {
    try {
      final token = await authRepository.getToken();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.adminReports}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (response.data as List)
          .map((json) => Report.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error loading reports: $e');
    }
  }

  /// Fetches the details for a single report by its ID.
  Future<Report> getReportDetails(int id) async {
    try {
      final token = await authRepository.getToken();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.adminReports}/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return Report.fromJson(response.data);
    } catch (e) {
      throw Exception('Error loading report details: $e');
    }
  }

  /// Sends a request to resolve a report with a specific action ('ban' or 'dismiss').
  Future<void> resolveReport(int id, String action, bool publicBlacklist) async {
    try {
      final token = await authRepository.getToken();
      await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.adminResolve}/$id/resolve',
        data: {'action': action, 'public_blacklist': publicBlacklist},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw Exception('Error resolving report: $e');
    }
  }
}
