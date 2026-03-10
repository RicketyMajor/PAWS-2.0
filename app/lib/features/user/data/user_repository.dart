// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/api_constants.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/user_model.dart';

/// Repository for handling all user profile-related API requests.
class UserRepository {
  final Dio _dio = Dio();
  final AuthRepository authRepository;

  UserRepository({required this.authRepository});

  /// A private helper to get authenticated request options.
  Future<Options> _getAuthOptions() async {
    final token = await authRepository.getToken();
    if (token == null) throw Exception('No active session');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // =========================================================================
  //  Profile Read
  // =========================================================================

  /// Fetches the complete profile (user and adopter profile) for the authenticated user.
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/profile',
        options: options,
      );
      return response.data;
    } catch (e) {
      throw Exception('Error loading profile: $e');
    }
  }

  /// Fetches the public profile for a user by their ID.
  Future<User> getUserById(int id) async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/users/$id',
        options: options,
      );
      return User.fromJson(response.data);
    } catch (e) {
      throw Exception('Error getting user: $e');
    }
  }

  // =========================================================================
  //  Profile Write
  // =========================================================================

  /// Updates the user's full profile data.
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
          "name": name, "bio": bio, "phone": phone, "photo_url": photoUrl,
          "housing_type": housingType, "housing_ownership": housingOwnership,
          "has_yard": hasYard, "has_fence": hasFence,
          "family_composition": familyComposition, "other_pets": otherPets,
          "time_availability": timeAvailability, "experience": experience,
        },
      );
    } catch (e) {
      throw Exception('Error updating profile: $e');
    }
  }

  /// Uploads a profile picture and returns the new URL.
  Future<String> uploadProfilePicture(XFile file) async {
    try {
      final options = await _getAuthOptions();
      final bytes = await file.readAsBytes(); // Read file as bytes for cross-platform compatibility.

      FormData formData = FormData.fromMap({
        "file": MultipartFile.fromBytes(bytes, filename: file.name),
      });

      final response = await _dio.post(
        '${ApiConstants.baseUrl}/files/upload',
        data: formData,
        options: options,
      );
      return response.data['url'];
    } catch (e) {
      throw Exception('Error uploading image: $e');
    }
  }

  // =========================================================================
  //  FCM Token
  // =========================================================================

  /// Saves the device's Firebase Cloud Messaging (FCM) token to the backend.
  Future<void> saveDeviceToken(String fcmToken) async {
    try {
      final token = await authRepository.getToken();
      if (token == null) return; // Don't proceed if not logged in.

      await _dio.post(
        '${ApiConstants.baseUrl}/notifications/token',
        data: {'token': fcmToken},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      print("Error saving FCM token: $e");
    }
  }
}
