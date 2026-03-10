// The domain layer contains the core models of the application.

/// Represents a pet available for adoption.
class Pet {
  final int id;
  final String name;
  final String type;
  final String breed;
  final int age;
  final String description;
  final String? imageUrl; // Main photo, often used as a cover.
  final List<String> images; // Full image gallery.

  // --- Owner (Rescuer) Information ---
  final int ownerId;
  final String ownerName;
  final String? ownerPhotoUrl;

  // --- Location ---
  final double latitude;
  final double longitude;
  final String address;

  // --- Health ---
  final bool isVaccinated;
  final bool isSterilized;
  final bool isDewormed;
  final String specialNeeds;

  // --- Compatibility & Lifestyle ---
  final bool goodWithKids;
  final bool goodWithDogs;
  final bool requiresYard;
  final String energyLevel;

  final String status;

  Pet({
    required this.id,
    required this.name,
    required this.type,
    required this.breed,
    required this.age,
    required this.description,
    this.imageUrl,
    this.images = const [],
    this.ownerId = 0,
    this.ownerName = 'User',
    this.ownerPhotoUrl,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.address = '',
    this.isVaccinated = false,
    this.isSterilized = false,
    this.isDewormed = false,
    this.specialNeeds = '',
    this.goodWithKids = false,
    this.goodWithDogs = false,
    this.requiresYard = false,
    this.energyLevel = 'medium',
    this.status = 'available',
  });

  /// Creates a [Pet] from a JSON map, with robust type parsing.
  factory Pet.fromJson(Map<String, dynamic> json) {
    // --- Private Parser Helpers for Type Safety ---
    int parseInt(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return false;
    }

    double parseDouble(dynamic v) {
      if (v is double) return v;
      if (v is String) return double.tryParse(v) ?? 0.0;
      if (v is int) return v.toDouble();
      return 0.0;
    }

    // --- 1. Process Image Gallery ---
    List<String> parsedImages = [];
    if (json['images'] != null && json['images'] is List) {
      parsedImages = (json['images'] as List).map((img) {
        // Handle cases where image is a map `{'url': '...'}` or just a string URL.
        if (img is Map && img['url'] != null) return img['url'].toString();
        return img.toString();
      }).toList();
    }
    // Fallback to the main photo URL if the gallery is empty.
    String? mainPhoto = json['photo_url'];
    if (parsedImages.isEmpty && mainPhoto != null && mainPhoto.isNotEmpty) {
      parsedImages.add(mainPhoto);
    }

    // --- 2. Process Nested Owner (User) Object ---
    int oId = 0;
    String oName = 'Unknown';
    String? oPhoto;

    if (json['user'] != null && json['user'] is Map) {
      final userJson = json['user'];
      oId = parseInt(userJson['id'] ?? userJson['ID']);
      oName = userJson['name'] ?? 'User';
      oPhoto = userJson['photo_url'];
    } else {
      // Fallback if the 'user' object was not preloaded by the API.
      oId = parseInt(json['user_id']);
    }

    // --- 3. Return the final Pet object ---
    return Pet(
      id: parseInt(json['id']),
      name: json['name'] ?? 'No Name',
      type: json['type'] ?? 'Dog',
      breed: json['breed'] ?? 'Mixed',
      age: parseInt(json['age']),
      description: json['description'] ?? '',
      imageUrl: mainPhoto,
      images: parsedImages,
      ownerId: oId,
      ownerName: oName,
      ownerPhotoUrl: oPhoto,
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      address: json['address'] ?? '',
      isVaccinated: parseBool(json['is_vaccinated']),
      isSterilized: parseBool(json['is_sterilized']),
      isDewormed: parseBool(json['is_dewormed']),
      specialNeeds: json['special_needs'] ?? '',
      goodWithKids: parseBool(json['good_with_kids']),
      goodWithDogs: parseBool(json['good_with_dogs']),
      requiresYard: parseBool(json['requires_yard']),
      energyLevel: json['energy_level'] ?? 'medium',
      status: json['status'] ?? 'available',
    );
  }
}
