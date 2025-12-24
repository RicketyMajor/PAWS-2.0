class Pet {
  final int id;
  final String name;
  final String type; // Dog, Cat
  final String breed;
  final int age;
  final String description;
  final String? imageUrl; // Puede ser null si no tiene foto
  // Nuevos campos de Fase 9 (Matchmaking)
  final bool goodWithKids;
  final bool goodWithDogs;
  final bool requiresYard;

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
  });

  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      breed: json['breed'] ?? 'Mestizo',
      age: json['age'] ?? 0,
      description: json['description'] ?? '',
      // Si el backend envía URL relativa (/uploads/...), concatenar base si es necesario
      // Ojo: En tu backend actual la URL viene en 'image_url' o similar, ajusta según JSON real
      imageUrl: json['image_url'],
      goodWithKids: json['good_with_kids'] ?? false,
      goodWithDogs: json['good_with_dogs'] ?? false,
      requiresYard: json['requires_yard'] ?? false,
    );
  }
}
