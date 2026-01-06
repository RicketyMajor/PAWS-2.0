class User {
  final int id;
  final String name;
  final String email;
  final String photoUrl;
  final String bio;
  final String phone;
  final String role;

  // --- DATOS DE VIVIENDA ---
  final String housingType; // House, Apartment, Parcel
  final String housingOwnership; // Owned, Rented
  final bool hasYard;
  final bool hasFence;

  // --- ESTILO DE VIDA ---
  final String familyComposition; // Single, Couple, Family w/Kids
  final String otherPets; // None, Dogs, Cats
  final String timeAvailability; // Low, Medium, High
  final String experience; // Beginner, Intermediate, Expert

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.bio,
    required this.phone,
    required this.role,
    this.housingType = 'House',
    this.housingOwnership = 'Owned',
    this.hasYard = false,
    this.hasFence = false,
    this.familyComposition = 'Single',
    this.otherPets = 'None',
    this.timeAvailability = 'Medium',
    this.experience = 'Beginner',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['ID'] ?? json['id'] ?? 0,
      name: json['name'] ?? 'Usuario',
      email: json['email'] ?? '',
      photoUrl: json['photo_url'] ?? '',
      bio: json['bio'] ?? '',
      phone: json['phone'] ?? '',
      role: json['role'] ?? 'adopter',

      // Mapeo seguro de los nuevos campos (con valores por defecto)
      housingType: json['housing_type'] ?? 'House',
      housingOwnership: json['housing_ownership'] ?? 'Owned',
      hasYard: json['has_yard'] ?? false,
      hasFence: json['has_fence'] ?? false,
      familyComposition: json['family_composition'] ?? 'Single',
      otherPets: json['other_pets'] ?? 'None',
      timeAvailability: json['time_availability'] ?? 'Medium',
      experience: json['experience'] ?? 'Beginner',
    );
  }
}
