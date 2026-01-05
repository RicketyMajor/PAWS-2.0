class Pet {
  final int id;
  final String name;
  final String type;
  final String breed;
  final int age;
  final String description;
  final String? imageUrl; // Mantenemos por compatibilidad (Portada)
  final List<String> images; // <--- NUEVA GALERÍA

  // Ubicación
  final double latitude;
  final double longitude;
  final String address;

  // Salud
  final bool isVaccinated;
  final bool isSterilized;
  final bool isDewormed;
  final String specialNeeds;

  // Compatibilidad / Estilo de Vida
  final bool goodWithKids;
  final bool goodWithDogs;
  final bool requiresYard;
  final String energyLevel; // low, medium, high

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

  factory Pet.fromJson(Map<String, dynamic> json) {
    // --- DEBUG LOGS (Espías) ---
    // Esto imprimirá en consola qué imágenes llegan realmente del backend
    print("PET_DEBUG [ID: ${json['id']}]: Parseando mascota '${json['name']}'");
    print(
      "PET_DEBUG [ID: ${json['id']}]: Campo 'images' crudo: ${json['images']}",
    );
    // ---------------------------

    // Helpers
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

    // Procesar Galería
    List<String> parsedImages = [];
    if (json['images'] != null && json['images'] is List) {
      parsedImages = (json['images'] as List).map((img) {
        // El backend devuelve objetos PetImage { "url": "..." }
        if (img is Map && img['url'] != null) return img['url'].toString();
        // Si por alguna razón llega como string directo
        return img.toString();
      }).toList();
    }

    // Fallback: Si no hay galería pero sí photo_url, la agregamos
    String? mainPhoto = json['photo_url'];
    if (parsedImages.isEmpty && mainPhoto != null && mainPhoto.isNotEmpty) {
      parsedImages.add(mainPhoto);
    }

    print(
      "PET_DEBUG [ID: ${json['id']}]: Galería final procesada (Length: ${parsedImages.length}): $parsedImages",
    );

    return Pet(
      id: parseInt(json['id']),
      name: json['name'] ?? 'Sin Nombre',
      type: json['type'] ?? 'Dog',
      breed: json['breed'] ?? 'Mestizo',
      age: parseInt(json['age']),
      description: json['description'] ?? '',
      imageUrl: mainPhoto,
      images: parsedImages,

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
