class Pet {
  final int id;
  final String name;
  final String type;
  final String breed;
  final int age;
  final String description;
  final String? imageUrl;
  final bool goodWithKids;
  final bool goodWithDogs;
  final bool requiresYard;
  final String status;

  Pet({
    required this.id,
    required this.name,
    required this.type,
    required this.breed,
    required this.age,
    required this.description,
    this.imageUrl,
    this.goodWithKids = false,
    this.goodWithDogs = false,
    this.requiresYard = false,
    this.status = 'available',
  });

  factory Pet.fromJson(Map<String, dynamic> json) {
    // Función auxiliar para forzar conversión a int
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    // Función auxiliar para bool
    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    }

    return Pet(
      id: parseInt(json['id']),
      name: json['name'] ?? 'Sin Nombre',
      type: json['type'] ?? 'Desconocido',
      breed: json['breed'] ?? 'Mestizo',
      age: parseInt(json['age']),
      description: json['description'] ?? '',
      imageUrl: json['image_url'],
      goodWithKids: parseBool(json['good_with_kids']),
      goodWithDogs: parseBool(json['good_with_dogs']),
      requiresYard: parseBool(json['requires_yard']),
      status: json['status'] ?? 'available',
    );
  }
}
