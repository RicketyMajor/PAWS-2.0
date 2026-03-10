// The data layer is responsible for interacting with data sources, like a REST API or local database.
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/api_constants.dart';
import '../domain/pet_model.dart';
import '../../auth/data/auth_repository.dart';

/// Repository for handling all pet-related API requests.
class PetsRepository {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  final AuthRepository authRepository;

  PetsRepository({required this.authRepository});

  /// A private helper to get authenticated request options.
  Future<Options> _getAuthOptions() async {
    final token = await authRepository.getToken();
    if (token == null) throw Exception('Invalid session');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ===============================================================
  //  Read Operations
  // ===============================================================

  /// Fetches the swipe deck of potential pet matches for the current user.
  Future<List<Pet>> getSwipeDeck({double? lat, double? lon}) async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.swipeDeck}',
        queryParameters: {
          if (lat != null) 'lat': lat,
          if (lon != null) 'lon': lon,
        },
        options: options,
      );

      if (response.statusCode == 200) {
        List<dynamic> data = response.data;
        return data.map((json) => Pet.fromJson(json)).toList();
      } else {
        throw Exception('Error loading pets');
      }
    } on DioException catch (e) {
      _handleError(e);
      return []; // Return empty list on error.
    }
  }

  /// Fetches all pets owned by the currently authenticated user.
  Future<List<Pet>> getMyPets() async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/pets/my',
        options: options,
      );

      if (response.statusCode == 200) {
        List<dynamic> data = response.data;
        return data.map((json) => Pet.fromJson(json)).toList();
      } else {
        throw Exception('Error loading your pets');
      }
    } on DioException catch (e) {
      _handleError(e);
      return [];
    }
  }

  /// Fetches a single pet by its ID.
  Future<Pet> getPetById(int id) async {
    try {
      final options = await _getAuthOptions();
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/pets/$id',
        options: options,
      );
      return Pet.fromJson(response.data);
    } catch (e) {
      throw Exception('Error getting pet: $e');
    }
  }

  // ===============================================================
  //  Write Operations
  // ===============================================================

  /// Creates a new pet profile with associated images.
  Future<void> createPet({
    required String name,
    required String type,
    required String breed,
    required int age,
    required String description,
    required double latitude,
    required double longitude,
    required List<XFile> images,
    bool isVaccinated = false,
    bool isSterilized = false,
    bool isDewormed = false,
    String specialNeeds = '',
    bool requiresYard = false,
    bool goodWithKids = false,
    bool goodWithDogs = false,
    String energyLevel = 'Medium',
    String address = '',
  }) async {
    try {
      final options = await _getAuthOptions();

      // Create FormData to send multipart request.
      FormData formData = FormData.fromMap({
        "name": name, "type": type, "breed": breed, "age": age,
        "description": description, "latitude": latitude, "longitude": longitude,
        "address": address, "is_vaccinated": isVaccinated, "is_sterilized": isSterilized,
        "is_dewormed": isDewormed, "special_needs": specialNeeds, "requires_yard": requiresYard,
        "good_with_kids": goodWithKids, "good_with_dogs": goodWithDogs, "energy_level": energyLevel,
      });

      // Convert each XFile image to in-memory bytes for universal compatibility.
      for (var file in images) {
        final bytes = await file.readAsBytes();
        formData.files.add(MapEntry("images", MultipartFile.fromBytes(bytes, filename: file.name)));
      }

      await _dio.post(
        '${ApiConstants.baseUrl}/pets',
        data: formData,
        options: options,
      );
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  /// Deletes a pet by its ID.
  Future<void> deletePet(int petId) async {
    try {
      final options = await _getAuthOptions();
      await _dio.delete(
        '${ApiConstants.baseUrl}/pets/$petId',
        options: options,
      );
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  // ===============================================================
  //  Interaction
  // ===============================================================

  /// Records a swipe action (like or dislike) on a pet.
  Future<void> swipePet({required int petId, required bool isLike}) async {
    try {
      final options = await _getAuthOptions();
      await _dio.post(
        '${ApiConstants.baseUrl}${ApiConstants.swipeAction}',
        options: options,
        data: {'pet_id': petId, 'is_like': isLike},
      );
    } catch (e) {
      print("Error on swipe: $e");
    }
  }

  /// Private helper to parse Dio errors and throw a more specific exception.
  void _handleError(DioException e) {
    String errorMessage = 'Connection error';
    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map<String, dynamic>) {
        errorMessage = data['error'] ?? errorMessage;
      } else {
        errorMessage = data.toString();
      }
    }
    print("PETS REPO ERROR: $errorMessage");
    throw Exception(errorMessage);
  }
}
