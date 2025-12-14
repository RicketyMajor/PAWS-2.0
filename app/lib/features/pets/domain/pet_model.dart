class Pet {
  final int id; // Go usa uint, aquí int está bien
  final String name;
  final String type;
  final String breed;
  final int age;
  final String description;
  final String status;
  // Agregamos imagen por defecto si no viene una
  final String imageUrl;

  Pet({
    required this.id,
    required this.name,
    required this.type,
    required this.breed,
    required this.age,
    required this.description,
    required this.status,
    required this.imageUrl,
  });

  // Factory para crear una Mascota desde el JSON de Go
  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      id: json['ID'] ?? 0, // Go devuelve mayúsculas (ID, Name, etc)
      name: json['Name'] ?? 'Sin nombre',
      type: json['Type'] ?? '',
      breed: json['Breed'] ?? '',
      age: json['Age'] ?? 0,
      description: json['Description'] ?? '',
      status: json['Status'] ?? 'Available',
      // Si el backend no manda foto, usamos una de placeholder
      imageUrl:
          json['ImageURL'] != null && json['ImageURL'].toString().isNotEmpty
          ? json['ImageURL']
          : 'https://images.unsplash.com/photo-1543466835-00a7907e9de1?auto=format&fit=crop&q=80&w=1000',
    );
  }
}
